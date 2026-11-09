#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PROXY_PATH = "/home/user/scale_to_zero_proxy.py"
BACKEND_PATH = "/home/user/analytics_service.py"
CONF_PATH = "/home/user/supervisor.conf"
START_LOG = "/tmp/finops_backend_starts.log"
SECRET = secrets.token_hex(24)


def test_bashrc_env_var():
    """Check that FINOPS_PROXY_PORT=8080 is in /home/user/.bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert re.search(r"FINOPS_PROXY_PORT\s*=\s*8080", content) or "FINOPS_PROXY_PORT=8080" in content, \
        "FINOPS_PROXY_PORT=8080 not found in /home/user/.bashrc."


def test_proxy_script_exists():
    """Check that the proxy script exists."""
    assert os.path.exists(PROXY_PATH), f"{PROXY_PATH} does not exist."
    assert os.path.isfile(PROXY_PATH), f"{PROXY_PATH} is not a regular file."
    subprocess.run(["python3", "-m", "py_compile", PROXY_PATH], check=True)


def test_supervisor_conf_exists_and_valid():
    """Check that supervisor.conf exists and has required sections."""
    assert os.path.exists(CONF_PATH), f"{CONF_PATH} does not exist."
    with open(CONF_PATH, "r") as f:
        content = f.read()
    assert "[program:finops_proxy]" in content, "Missing [program:finops_proxy] in supervisor.conf"
    assert "scale_to_zero_proxy.py" in content, "Proxy script not referenced in supervisor.conf"
    assert "autorestart=true" in content.lower(), "autorestart=true not found in supervisor.conf"
    assert re.search(r"(?im)^\s*environment\s*=.*FINOPS_PROXY_PORT\s*=\s*[\"']?8080", content), \
        "supervisor.conf must provide FINOPS_PROXY_PORT=8080 because supervisord does not source .bashrc"


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Port {port} did not become available")


def request(path, timeout=15):
    req = urllib.request.Request("http://127.0.0.1:8080" + path)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.getcode(), response.read()
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to proxy or proxy returned error: {e}")


def backend_body(path):
    digest = hashlib.sha256((SECRET + path).encode("utf-8")).hexdigest()
    return ("BACKEND_RESPONSE:" + digest + ":" + path).encode("utf-8")


def start_count():
    try:
        with open(START_LOG, "r") as f:
            return len(f.readlines())
    except FileNotFoundError:
        return 0


@pytest.fixture(scope="module")
def run_supervisor():
    """Install an unpredictable test backend, start supervisord, and clean up."""
    with open(BACKEND_PATH, "rb") as f:
        original_backend = f.read()
    original_mode = os.stat(BACKEND_PATH).st_mode

    backend_source = f'''import hashlib
import http.server
import os
import time

SECRET = {SECRET!r}
START_LOG = {START_LOG!r}

class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            status = 200
            body = b"ANALYTICS_COST_SAVINGS_ACTIVE"
        else:
            status = 207
            digest = hashlib.sha256((SECRET + self.path).encode("utf-8")).hexdigest()
            body = ("BACKEND_RESPONSE:" + digest + ":" + self.path).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

with open(START_LOG, "a") as f:
    f.write(str(os.getpid()) + "\\n")
    f.flush()
time.sleep(1.2)
with Server(("127.0.0.1", 9090), Handler) as server:
    server.serve_forever()
'''

    subprocess.run(["pkill", "-f", "supervisord"], capture_output=True)
    subprocess.run(["pkill", "-f", "scale_to_zero_proxy.py"], capture_output=True)
    subprocess.run(["pkill", "-f", "analytics_service.py"], capture_output=True)
    time.sleep(0.3)
    try:
        os.unlink(START_LOG)
    except FileNotFoundError:
        pass
    with open(BACKEND_PATH, "w") as f:
        f.write(backend_source)
    os.chmod(BACKEND_PATH, original_mode)

    env = os.environ.copy()
    env.pop("FINOPS_PROXY_PORT", None)
    proc = subprocess.Popen(["supervisord", "-c", CONF_PATH], env=env)
    time.sleep(3)

    try:
        yield proc
    finally:
        subprocess.run(["pkill", "-f", "supervisord"], capture_output=True)
        subprocess.run(["pkill", "-f", "scale_to_zero_proxy.py"], capture_output=True)
        subprocess.run(["pkill", "-f", "analytics_service.py"], capture_output=True)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        with open(BACKEND_PATH, "wb") as f:
            f.write(original_backend)
        os.chmod(BACKEND_PATH, original_mode)


def test_proxy_behavior(run_supervisor):
    """Exercise wake-up, polling, forwarding, and already-running behavior."""
    check_proxy = subprocess.run(["pgrep", "-f", "scale_to_zero_proxy.py"], capture_output=True, text=True)
    assert check_proxy.returncode == 0, "scale_to_zero_proxy.py is not running via supervisord."

    check_backend_initial = subprocess.run(["pgrep", "-f", "analytics_service.py"], capture_output=True, text=True)
    assert check_backend_initial.returncode != 0, \
        "analytics_service.py should not be running before the first request."

    started = time.monotonic()
    status, body = request("/")
    elapsed = time.monotonic() - started
    assert status == 200, f"Expected status 200, got {status}"
    assert b"ANALYTICS_COST_SAVINGS_ACTIVE" in body, "Response body did not match expected output."
    assert body == b"ANALYTICS_COST_SAVINGS_ACTIVE", "Proxy did not preserve the exact backend body."
    assert elapsed >= 0.9, "Proxy returned before the deliberately delayed backend became available."

    check_backend_final = subprocess.run(["pgrep", "-f", "analytics_service.py"], capture_output=True, text=True)
    assert check_backend_final.returncode == 0, "analytics_service.py was not spawned by the proxy."

    dynamic_path = "/reports/" + secrets.token_hex(12) + "?window=37&group=cloud"
    status, body = request(dynamic_path)
    assert status == 207, f"Expected backend status 207, got {status}"
    assert body == backend_body(dynamic_path), \
        "Proxy did not forward the request path/query or preserve the exact backend response."

    subprocess.run(["pkill", "-f", "analytics_service.py"], capture_output=True)
    deadline = time.time() + 5
    while time.time() < deadline:
        if subprocess.run(["pgrep", "-f", "analytics_service.py"], capture_output=True).returncode != 0:
            break
        time.sleep(0.05)

    manual_backend = subprocess.Popen(["python3", BACKEND_PATH])
    try:
        wait_for_port(9090, timeout=8)
        starts_before = start_count()
        existing_path = "/already-running/" + secrets.token_hex(12) + "?mode=existing"
        status, body = request(existing_path)
        assert status == 207, f"Expected backend status 207, got {status}"
        assert body == backend_body(existing_path), "Proxy did not forward to the already-running backend."
        time.sleep(0.5)
        assert start_count() == starts_before, \
            "Proxy spawned another analytics service even though the backend was already responding."
    finally:
        manual_backend.terminate()
        try:
            manual_backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            manual_backend.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
