#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import gzip
import os
import re
import signal
import ssl
import struct
import subprocess
import tempfile
import time
import urllib.request
import uuid

HOME = "/home/user"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def https_get(path):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url = "https://127.0.0.1:8443/" + path.lstrip("/")
    with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
        return response.status, response.read().decode("utf-8")


def wait_for_https(path, expected, timeout=12):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            status, content = https_get(path)
            if status == 200 and expected in content:
                return
            last = f"status={status}, content={content!r}"
        except Exception as exc:
            last = repr(exc)
        time.sleep(0.25)
    raise AssertionError(f"HTTPS server did not serve expected content: {last}")


def server_pids():
    found = set()
    for path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            raw = open(path, "rb").read()
            args = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
            if any(arg == "/home/user/server.py" for arg in args):
                found.add(int(path.split("/")[2]))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return found


def wait_pids_gone(pids, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        alive = {pid for pid in pids if os.path.exists(f"/proc/{pid}")}
        if not alive:
            return
        time.sleep(0.1)
    raise AssertionError(f"Old server.py processes were not stopped: {sorted(alive)}")


def wait_new_server(old_pids, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        new = server_pids() - old_pids
        if new:
            time.sleep(0.5)
            new = {pid for pid in new if os.path.exists(f"/proc/{pid}")}
            if new:
                return new
        time.sleep(0.1)
    raise AssertionError("deploy.sh did not leave a new detached server.py process running")


def deployment_target():
    assert os.path.islink(f"{HOME}/www-current")
    target = os.path.realpath(f"{HOME}/www-current")
    assert os.path.dirname(target) == f"{HOME}/deployments", target
    assert os.path.isdir(target), target
    return target


def assert_release_is_clone(target, expected_head):
    assert os.path.exists(os.path.join(target, ".git")), "Release is not a Git clone"
    head = run(["git", "-C", target, "rev-parse", "HEAD"]).stdout.strip()
    assert head == expected_head, f"Release HEAD {head} != repository HEAD {expected_head}"
    origin = run(["git", "-C", target, "remote", "get-url", "origin"]).stdout.strip()
    assert os.path.realpath(origin) == f"{HOME}/site_repo.git", origin


def start_atomic_watch():
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, os.strerror(ctypes.get_errno())
    mask = 0x00000100 | 0x00000200 | 0x00000040 | 0x00000080  # CREATE, DELETE, MOVED_FROM, MOVED_TO
    wd = libc.inotify_add_watch(fd, HOME.encode(), mask)
    assert wd >= 0, os.strerror(ctypes.get_errno())
    return fd


def read_atomic_events(fd):
    data = b""
    while True:
        try:
            data += os.read(fd, 65536)
        except BlockingIOError:
            break
    os.close(fd)
    events = []
    offset = 0
    while offset + 16 <= len(data):
        wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
        offset += 16
        name = data[offset:offset + length].split(b"\0", 1)[0].decode(errors="replace")
        offset += length
        if name == "www-current":
            events.append(mask)
    return events


def test_directories_exist():
    expected_dirs = [
        "/home/user/deployments",
        "/home/user/certs",
        "/home/user/logs"
    ]
    for d in expected_dirs:
        assert os.path.isdir(d), f"Required directory {d} is missing"


def test_tls_certs_exist():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing"
    assert os.path.isfile(key_path), f"Key file {key_path} is missing"

    cert_info = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer"]).stdout
    subject = re.search(r"^subject\s*=\s*(.*)$", cert_info, re.M)
    issuer = re.search(r"^issuer\s*=\s*(.*)$", cert_info, re.M)
    assert subject and issuer and subject.group(1) == issuer.group(1), "Certificate is not self-signed"

    pub_info = run(["openssl", "x509", "-in", cert_path, "-noout", "-text"]).stdout
    assert "Public-Key: (2048 bit)" in pub_info and "rsaEncryption" in pub_info, "Certificate is not RSA-2048"
    cert_pub = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]).stdout
    key_pub = run(["openssl", "pkey", "-in", key_path, "-pubout"]).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_deploy_script():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Deployment script {script_path} is not executable"
    assert os.path.isfile("/home/user/server.py"), "Server script /home/user/server.py is missing"


def test_symlink_and_content():
    symlink_path = "/home/user/www-current"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"

    target = os.readlink(symlink_path)
    assert target.startswith("/home/user/deployments/"), f"Symlink {symlink_path} does not point to a deployment directory"

    index_path = os.path.join(symlink_path, "index.html")
    assert os.path.isfile(index_path), f"index.html not found in {symlink_path}"


def test_server_running_and_serving():
    try:
        status, content = https_get("index.html")
        assert status == 200, f"Server returned status {status}"
        assert "Deployment Successful" in content, "Server is not serving the correct index.html content"
    except Exception as e:
        assert False, f"Failed to connect to the server at https://127.0.0.1:8443/index.html: {e}"


def test_deployment_pipeline_execution():
    nonce = "verifier-" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="repo-update-") as work:
        run(["git", "clone", f"{HOME}/site_repo.git", work])
        run(["git", "-C", work, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", work, "config", "user.name", "Verifier"])
        with open(os.path.join(work, "index.html"), "w") as f:
            f.write(f"<h1>Deployment Successful</h1>\n<p>{nonce}</p>\n")
        run(["git", "-C", work, "add", "index.html"])
        run(["git", "-C", work, "commit", "-m", nonce])
        run(["git", "-C", work, "push", "origin", "HEAD:master"])
    expected_head = run(["git", "--git-dir", f"{HOME}/site_repo.git", "rev-parse", "HEAD"]).stdout.strip()

    old_target = deployment_target()
    old_pids = server_pids()
    assert old_pids, "No initial server.py process was running"

    term_marker = f"/tmp/{nonce}.terminated"
    decoy_code = (
        "import signal,time,sys; "
        f"signal.signal(signal.SIGTERM, lambda s,f: (open({term_marker!r},'w').write('TERM'),sys.exit(0))); "
        "open(sys.argv[2],'w').write('ready'); "
        "time.sleep(60)"
    )
    ready = f"/tmp/{nonce}.ready"
    decoy = subprocess.Popen(["python3", "-c", decoy_code, "/home/user/server.py", ready])
    try:
        deadline = time.time() + 3
        while not os.path.exists(ready) and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.exists(ready), "Could not start lifecycle probe"
        old_pids.add(decoy.pid)

        run([f"{HOME}/deploy.sh"], timeout=30)
        wait_pids_gone(old_pids)
        assert os.path.isfile(term_marker), "Existing server.py process was not stopped gracefully with SIGTERM"
        first_pids = wait_new_server(old_pids)
        first_target = deployment_target()
        assert first_target != old_target, "deploy.sh did not create and activate a new release"
        assert_release_is_clone(first_target, expected_head)
        wait_for_https("index.html", nonce)

        probe_name = nonce + ".txt"
        with open(os.path.join(first_target, probe_name), "w") as f:
            f.write(nonce)
        wait_for_https(probe_name, nonce)

        watch_fd = start_atomic_watch()
        run([f"{HOME}/deploy.sh"], timeout=30)
        events = read_atomic_events(watch_fd)
        wait_pids_gone(first_pids)
        second_pids = wait_new_server(first_pids)
        second_target = deployment_target()
        assert second_target != first_target, "Two deploy.sh runs reused the same release directory"
        assert_release_is_clone(second_target, expected_head)

        IN_CREATE = 0x00000100
        IN_DELETE = 0x00000200
        IN_MOVED_TO = 0x00000080
        assert events, "deploy.sh did not replace www-current on its second run"
        assert any(mask & IN_MOVED_TO for mask in events), "www-current was not installed by an atomic rename"
        assert not any(mask & (IN_CREATE | IN_DELETE) for mask in events), "www-current was removed/recreated non-atomically"

        wait_for_https("index.html", nonce)
        assert second_pids, "No replacement server process remained running"
        assert os.path.isfile(f"{HOME}/logs/server.log"), "Server log is missing"
        assert os.path.getsize(f"{HOME}/logs/server.log") > 0, "Server did not write to server.log"
    finally:
        if decoy.poll() is None:
            decoy.terminate()
            try:
                decoy.wait(timeout=2)
            except subprocess.TimeoutExpired:
                decoy.kill()


def test_logrotate_files():
    conf_path = "/home/user/logrotate.conf"
    state_path = "/home/user/logrotate.state"

    assert os.path.isfile(conf_path), f"logrotate configuration {conf_path} is missing"
    assert os.path.isfile(state_path), f"logrotate state file {state_path} is missing"

    rotated_logs = glob.glob("/home/user/logs/server.log.*")
    assert len(rotated_logs) > 0, "No rotated log files found in /home/user/logs/"

    text = open(conf_path).read()
    uncommented = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    match = re.search(r"(?ms)^\s*[\"']?/home/user/logs/server\.log[\"']?\s*\{(.*?)^\s*\}", uncommented)
    assert match, "logrotate.conf has no block for /home/user/logs/server.log"
    body = match.group(1)
    assert re.search(r"(?m)^\s*daily\s*$", body), "logrotate config is missing daily"
    assert re.search(r"(?m)^\s*rotate\s+3\s*$", body), "logrotate config must keep exactly 3 copies"
    for directive in ("compress", "missingok", "notifempty"):
        assert re.search(rf"(?m)^\s*{directive}\s*$", body), f"logrotate config is missing {directive}"

    marker = "rotation-" + uuid.uuid4().hex
    with open(f"{HOME}/logs/server.log", "a") as f:
        f.write(marker + "\n")
    verifier_state = f"{HOME}/.verifier-logrotate.state"
    try:
        os.unlink(verifier_state)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "logrotate", "--force", "--state", verifier_state, conf_path],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"logrotate failed with the submitted config: {result.stderr}"
    assert os.path.isfile(verifier_state), "logrotate did not create the requested local state file"

    found = False
    for path in glob.glob(f"{HOME}/logs/server.log.*.gz") + glob.glob(f"{HOME}/logs/server.log.gz"):
        try:
            with gzip.open(path, "rt", errors="replace") as f:
                if marker in f.read():
                    found = True
                    break
        except (OSError, EOFError):
            pass
    assert found, "Forced logrotate run did not create a compressed archive containing the live log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
