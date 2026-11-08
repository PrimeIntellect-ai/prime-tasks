#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import ssl
import subprocess
import sys
import time
import urllib.request
import uuid
import pytest

SCRIPT_PATH = "/home/user/deploy.sh"


def listener_pids(port):
    """Return PIDs owning an IPv4/IPv6 listening socket on port."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def wait_for_listener(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def run_deploy():
    return subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True, timeout=60)


def test_deploy_script_idempotent():
    assert os.path.isfile(SCRIPT_PATH), f"Deploy script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK) or SCRIPT_PATH.endswith(".sh"), f"Deploy script {SCRIPT_PATH} should be executable or runnable via bash"

    res1 = run_deploy()
    assert res1.returncode == 0, f"Deploy script failed on first run:\nSTDOUT:\n{res1.stdout}\nSTDERR:\n{res1.stderr}"

    res2 = run_deploy()
    assert res2.returncode == 0, f"Deploy script failed on second run (idempotency check):\nSTDOUT:\n{res2.stdout}\nSTDERR:\n{res2.stderr}"


def test_index_html():
    path = "/home/user/www/index.html"
    assert os.path.isfile(path), f"File {path} not found"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "OK", f"Expected index.html to contain 'OK', got '{content}'"


def test_patched_package_is_installed_and_running():
    source = "/app/fast-forwarder/fast_forwarder/server.py"
    venv_python = "/home/user/venv/bin/python"
    console_script = "/home/user/venv/bin/fast-forwarder"
    assert os.path.isfile(source), "fast-forwarder source is missing"
    assert os.path.isfile(venv_python), "Python virtual environment is missing"
    assert os.path.isfile(console_script), "fast-forwarder is not installed in the virtual environment"

    with open(source, "rb") as f:
        source_bytes = f.read()
    assert b"await asyncio.sleep(0.05)" not in source_bytes, "The artificial per-connection delay remains in /app/fast-forwarder"

    probe = subprocess.run(
        [venv_python, "-c", "import fast_forwarder.server as s; print(s.__file__)"],
        capture_output=True, text=True, timeout=10
    )
    assert probe.returncode == 0, f"Cannot import installed fast-forwarder: {probe.stderr}"
    installed_source = probe.stdout.strip()
    assert os.path.realpath(installed_source).startswith(os.path.realpath("/home/user/venv") + os.sep), \
        f"fast-forwarder was not installed into the requested virtual environment: {installed_source}"
    with open(installed_source, "rb") as f:
        assert f.read() == source_bytes, "The virtual environment does not contain the patched /app/fast-forwarder source"

    pids = wait_for_listener(8443)
    assert pids, "Nothing is listening on port 8443"
    valid = False
    diagnostics = []
    for pid in pids:
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            argv = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
        except OSError:
            continue
        diagnostics.append(argv)
        real_args = [os.path.realpath(a) for a in argv if a.startswith("/")]
        required = ["--bind", "127.0.0.1", "--port", "8443", "--cert", "/home/user/tls/cert.pem", "--key", "/home/user/tls/key.pem", "--forward", "127.0.0.1:8080"]
        if os.path.realpath(console_script) in real_args and all(item in argv for item in required):
            valid = True
            break
    assert valid, f"Port 8443 is not owned by the installed fast-forwarder command with the required arguments: {diagnostics}"


def test_services_running():
    time.sleep(2)

    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3)
        content = req.read().decode("utf-8").strip()
        assert content == "OK", f"Backend server returned unexpected content: {content}"
    except Exception as e:
        pytest.fail(f"Backend server on 8080 is not responding correctly: {e}")

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.urlopen("https://127.0.0.1:8443/", context=ctx, timeout=3)
        content = req.read().decode("utf-8").strip()
        assert content == "OK", f"Proxy server returned unexpected content: {content}"
    except Exception as e:
        pytest.fail(f"Proxy server on 8443 is not responding correctly: {e}")


def test_proxy_really_forwards_to_port_8080():
    # Replace the ordinary backend temporarily with a verifier-controlled backend.
    # Its unpredictable path, body, header, and request-header echo establish that
    # the TLS listener is forwarding traffic rather than serving a fixed response.
    for pid in listener_pids(8080):
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while listener_pids(8080) and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(8080), "Could not stop the deployed backend for forwarding test"

    token = uuid.uuid4().hex
    path = "/probe-" + uuid.uuid4().hex
    header_value = uuid.uuid4().hex
    backend_code = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
path, token = sys.argv[1], sys.argv[2]
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != path:
            self.send_response(404); self.end_headers(); return
        echoed = self.headers.get("X-Verifier-Probe", "")
        body = (token + ":" + echoed).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend-Token", token)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
'''
    backend = subprocess.Popen(
        [sys.executable, "-c", backend_code, path, token],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        assert wait_for_listener(8080, 5), "Verifier-controlled backend failed to start"
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        request = urllib.request.Request(
            "https://127.0.0.1:8443" + path,
            headers={"X-Verifier-Probe": header_value},
        )
        response = urllib.request.urlopen(request, context=ctx, timeout=5)
        body = response.read().decode()
        assert response.status == 200
        assert response.headers.get("X-Backend-Token") == token, "Proxy response did not come from the port 8080 backend"
        assert body == token + ":" + header_value, "Proxy did not relay the backend response and request header"
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=5)
        except subprocess.TimeoutExpired:
            backend.kill()
            backend.wait(timeout=5)

        restored = run_deploy()
        assert restored.returncode == 0, f"Deployment could not restore services after forwarding test:\n{restored.stdout}\n{restored.stderr}"
        assert wait_for_listener(8080), "Backend was not restored after forwarding test"
        assert wait_for_listener(8443), "Proxy was not restored after forwarding test"


def test_throughput():
    cmd = ["ab", "-n", "500", "-c", "50", "-k", "https://127.0.0.1:8443/"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

    match = re.search(r"Requests per second:\s+([\d.]+)", result.stdout)
    assert match is not None, f"Could not parse 'Requests per second' from ab output:\n{result.stdout}\n{result.stderr}"

    rps = float(match.group(1))
    assert rps >= 200.0, f"Throughput is too low: {rps} RPS (expected >= 200.0). The artificial delay in the proxy might not be fully removed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
