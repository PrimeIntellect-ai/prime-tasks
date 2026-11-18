#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import time
import uuid
import socket
import shutil
import signal
import subprocess
import tempfile
import urllib.request

CERT = "/home/user/tls/cert.pem"
KEY = "/home/user/tls/key.pem"
APP = "/home/user/app"
PIDFILE = APP + "/server.pid"
CHECKER = "/home/user/checker"
FRESH_CHECKER = "/tmp/checker_verified"
LOG = "/home/user/system_status.log"
DEPLOY_FILE = APP + "/deploy_success.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def pid_alive(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return False


def read_pid():
    with open(PIDFILE) as f:
        text = f.read().strip()
    assert re.fullmatch(r"[1-9][0-9]*", text), "server.pid does not contain a valid PID"
    return int(text)


def wait_https(path="/", expected=200, timeout=8):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("https://127.0.0.1:8443" + path,
                                        context=ctx, timeout=1) as response:
                if response.status == expected:
                    return response.read()
        except Exception as exc:
            last = exc
        time.sleep(0.1)
    raise AssertionError(f"HTTPS endpoint did not become ready: {last}")


def wait_dead(pid, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not pid_alive(pid):
            return
        time.sleep(0.1)
    raise AssertionError(f"Old server PID {pid} was not terminated by the hook")


def assert_pid_owns_loopback_listener(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[([0-9]+)\]", target)
        if match:
            inodes.add(match.group(1))

    found = False
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            # 127.0.0.1:8443, LISTEN, and owned by the PID in server.pid.
            if local.upper() == "0100007F:20FB" and state == "0A" and inode in inodes:
                found = True
                break
    assert found, "server.pid does not own a listener bound to 127.0.0.1:8443"


def test_tls_certificates():
    assert os.path.isfile(CERT), "TLS certificate /home/user/tls/cert.pem is missing"
    assert os.path.isfile(KEY), "TLS private key /home/user/tls/key.pem is missing"

    key_data = open(KEY, "rb").read()
    assert b"ENCRYPTED" not in key_data, "TLS private key must be unencrypted"
    key_info = run(["openssl", "pkey", "-in", KEY, "-noout", "-text"],
                   input="", timeout=5).stdout
    assert "2048 bit" in key_info and "Private-Key" in key_info, "Private key is not 2048-bit"
    assert "RSA" in key_info or "modulus:" in key_info, "Private key is not RSA"

    cert_info = run(["openssl", "x509", "-in", CERT, "-noout", "-text"]).stdout
    assert "Public Key Algorithm: rsaEncryption" in cert_info, "Certificate does not contain an RSA key"
    assert "Public-Key: (2048 bit)" in cert_info, "Certificate RSA key is not 2048-bit"
    subject = run(["openssl", "x509", "-in", CERT, "-noout", "-subject"]).stdout.split("=", 1)[-1].strip()
    issuer = run(["openssl", "x509", "-in", CERT, "-noout", "-issuer"]).stdout.split("=", 1)[-1].strip()
    assert subject == issuer, "Certificate is not self-signed"
    run(["openssl", "verify", "-CAfile", CERT, CERT])

    cert_pub = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"]).stdout
    key_pub = run(["openssl", "pkey", "-in", KEY, "-pubout"], input="", timeout=5).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_git_repo_and_hook():
    assert os.path.isdir("/home/user/monitor.git"), "Git bare repository /home/user/monitor.git is missing"
    assert run(["git", "-C", "/home/user/monitor.git", "rev-parse", "--is-bare-repository"]).stdout.strip() == "true", "monitor.git is not a bare Git repository"
    hook_path = "/home/user/monitor.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} is missing"
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable"
    assert os.path.isdir("/home/user/workspace"), "Git workspace /home/user/workspace is missing"


def test_deployed_files():
    assert os.path.isdir(APP), "Deployment directory /home/user/app is missing"
    assert os.path.isfile(APP + "/server.py"), "server.py is missing in /home/user/app"
    assert os.path.isfile(DEPLOY_FILE), "deploy_success.txt is missing in /home/user/app"
    assert os.path.isfile(PIDFILE), "server.pid is missing in /home/user/app"
    run(["python3", "-m", "py_compile", APP + "/server.py"])
    pid = read_pid()
    assert pid_alive(pid), "PID in server.pid is not a running process"
    cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    assert "python" in cmdline.lower() and "server.py" in cmdline, "server.pid does not identify the Python server"
    wait_https()
    assert_pid_owns_loopback_listener(pid)


def test_post_receive_hook_behavior():
    old_pid = read_pid()
    assert pid_alive(old_pid), "Server was not running before the deployment test"
    token = uuid.uuid4().hex
    marker_name = "verifier_marker.txt"
    clone_dir = tempfile.mkdtemp(prefix="hook-clone-")
    try:
        run(["git", "clone", "--branch", "master", "/home/user/monitor.git", clone_dir])
        run(["git", "-C", clone_dir, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", clone_dir, "config", "user.name", "Verifier"])
        with open(os.path.join(clone_dir, marker_name), "w") as f:
            f.write(token)
        run(["git", "-C", clone_dir, "add", marker_name])
        run(["git", "-C", clone_dir, "commit", "-m", "Verifier deployment probe"])
        run(["git", "-C", clone_dir, "push", "origin", "master"], timeout=20)
    finally:
        shutil.rmtree(clone_dir, ignore_errors=True)

    deployed_marker = os.path.join(APP, marker_name)
    assert os.path.isfile(deployed_marker), "post-receive hook did not check out the pushed commit into /home/user/app"
    assert open(deployed_marker).read() == token, "Deployed content is not the content that was pushed"
    new_pid = read_pid()
    assert new_pid != old_pid, "post-receive hook did not replace the old server process"
    wait_dead(old_pid)
    assert pid_alive(new_pid), "New PID written by post-receive is not running"
    cmdline = open(f"/proc/{new_pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    assert "python" in cmdline.lower() and "server.py" in cmdline, "Hook did not start the Python server"
    body = wait_https("/" + marker_name)
    assert body.decode() == token, "Server is not serving the deployed /home/user/app working tree"
    assert_pid_owns_loopback_listener(new_pid)


def test_web_server_listening():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request("https://127.0.0.1:8443/")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
    except Exception as e:
        assert False, f"Failed to connect to the HTTPS server on 127.0.0.1:8443: {e}"


def test_c_program_compilation():
    assert os.path.isfile("/home/user/checker.c"), "C source file /home/user/checker.c is missing"
    assert os.path.isfile(CHECKER), "Compiled C program /home/user/checker is missing"
    assert os.access(CHECKER, os.X_OK), "Compiled C program /home/user/checker is not executable"
    source = open("/home/user/checker.c", errors="replace").read()
    assert re.search(r"\bfopen\s*\(", source), "checker.c does not use standard C file I/O"
    run(["gcc", "/home/user/checker.c", "-o", FRESH_CHECKER, "-lcurl"], timeout=20)
    assert open(FRESH_CHECKER, "rb").read(4) == b"\x7fELF", "checker.c did not compile to an ELF executable"
    assert "libcurl" in run(["ldd", FRESH_CHECKER]).stdout, "Freshly compiled checker is not linked to libcurl"
    assert "libcurl" in run(["ldd", CHECKER]).stdout, "Submitted checker binary is not linked to libcurl"


def test_log_file_content():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing"
    with open(LOG, "r") as f:
        content = f.read()
    assert "SYSTEM: OK" in content, f"'SYSTEM: OK' not found in {LOG}"


def test_c_program_behavior_dynamically():
    if os.path.exists(LOG):
        os.remove(LOG)
    subprocess.run([CHECKER], check=True, timeout=10)
    assert os.path.isfile(LOG), f"Checker did not create {LOG}"
    with open(LOG, "r") as f:
        content = f.read()
    assert "SYSTEM: OK" in content, "Checker did not log 'SYSTEM: OK' when everything is fine"

    os.remove(DEPLOY_FILE)
    try:
        subprocess.run([CHECKER], check=True, timeout=10)
        with open(LOG, "r") as f:
            content = f.read()
        assert "SYSTEM: FAIL" in content, "Checker did not log 'SYSTEM: FAIL' when deploy_success.txt is missing"
    finally:
        open(DEPLOY_FILE, "w").close()


def test_freshly_compiled_checker_independently_checks_https_and_file():
    helper_script = "/tmp/verifier_https.py"
    with open(helper_script, "w") as f:
        f.write(r'''import http.server, ssl, sys
class Server(http.server.HTTPServer):
    allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(int(sys.argv[1]))
        self.send_header("Content-Length", "0")
        self.end_headers()
    def log_message(self, *args):
        pass
server = Server(("127.0.0.1", 8443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[2], sys.argv[3])
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
''')

    deployed_pid = read_pid()
    helper = None

    def stop_process(proc):
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)

    def start_helper(status):
        proc = subprocess.Popen(["python3", helper_script, str(status), CERT, KEY],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 5
        while time.time() < deadline:
            if proc.poll() is not None:
                raise AssertionError("Controlled HTTPS server exited early")
            try:
                with socket.create_connection(("127.0.0.1", 8443), timeout=0.2):
                    return proc
            except OSError:
                time.sleep(0.05)
        stop_process(proc)
        raise AssertionError("Controlled HTTPS server did not start")

    def run_and_expect(expected, previous):
        subprocess.run([FRESH_CHECKER], check=True, timeout=10)
        content = open(LOG).read()
        assert content == previous + expected + "\n", f"Expected checker to append exactly {expected!r}, got {content!r}"
        return content

    previous = "VERIFIER-SENTINEL\n"
    with open(LOG, "w") as f:
        f.write(previous)

    try:
        os.kill(deployed_pid, signal.SIGTERM)
        wait_dead(deployed_pid)

        # A present file cannot produce OK when the HTTPS connection fails.
        open(DEPLOY_FILE, "a").close()
        previous = run_and_expect("SYSTEM: FAIL", previous)

        # A valid TLS connection with a non-200 response must still fail.
        helper = start_helper(503)
        previous = run_and_expect("SYSTEM: FAIL", previous)
        stop_process(helper)
        helper = None
        time.sleep(0.2)

        # HTTPS 200 plus the file succeeds.
        helper = start_helper(200)
        previous = run_and_expect("SYSTEM: OK", previous)

        # The same HTTPS 200 must fail when the filesystem condition is absent.
        os.remove(DEPLOY_FILE)
        previous = run_and_expect("SYSTEM: FAIL", previous)
    finally:
        stop_process(helper)
        open(DEPLOY_FILE, "a").close()
        time.sleep(0.2)
        restored = subprocess.Popen(["python3", APP + "/server.py"], cwd=APP,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    start_new_session=True)
        with open(PIDFILE, "w") as f:
            f.write(str(restored.pid) + "\n")
        wait_https()
        assert pid_alive(restored.pid), "Failed to restore the deployed HTTPS server"
        assert_pid_owns_loopback_listener(restored.pid)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
