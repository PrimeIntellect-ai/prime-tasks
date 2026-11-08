#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'APP_EOF' > /tmp/expected_app.py
import os
import sys
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with open("config.json", "r") as f:
                config = json.load(f)
        except Exception:
            config = {}

        if os.environ.get("DEPLOY_ENV") != "production":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Error: Not in production")
            return

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()

        response = {"status": "ok", "message": "Backend operational", "config_loaded": config.get("proxy_active", False)}
        self.wfile.write(json.dumps(response).encode())

if __name__ == "__main__":
    if os.environ.get("DEPLOY_ENV") != "production":
        print("Crash: DEPLOY_ENV not set to production")
        sys.exit(1)

    # Simulate crashing if not in the right working directory
    if os.path.basename(os.getcwd()) != "app":
        print("Crash: Wrong working directory")
        sys.exit(1)

    server = HTTPServer(("localhost", 8081), BackendHandler)
    server.serve_forever()
APP_EOF

cat << 'PY_EOF' > /tmp/verify_artifacts.py
import json
import os
import secrets
import signal
import socket
import subprocess
import sys
import time
import urllib.request


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids(port):
    inodes = listener_inodes(port)
    result = set()
    if not inodes:
        return result
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def kill_port(port):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(port)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    if listener_pids(port):
        raise AssertionError(f"Could not clear port {port}")


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(port):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                    return
            except OSError:
                pass
        time.sleep(0.1)
    raise AssertionError(f"Port {port} did not start listening")


def read_proc(pid, name, binary=False):
    mode = "rb" if binary else "r"
    with open(f"/proc/{pid}/{name}", mode) as f:
        return f.read()


def verify_backend_process():
    pids = listener_pids(8081)
    assert len(pids) == 1, f"Expected one backend listener, found {pids}"
    pid = next(iter(pids))
    cmdline = read_proc(pid, "cmdline", True).split(b"\0")
    assert any(os.path.basename(x.decode(errors="replace")) == "app.py" for x in cmdline if x), \
        f"Backend listener is not app.py: {cmdline}"
    assert os.path.realpath(f"/proc/{pid}/cwd") == "/home/user/app", "Backend has the wrong working directory"
    environ = read_proc(pid, "environ", True).split(b"\0")
    assert b"DEPLOY_ENV=production" in environ, "Backend process lacks DEPLOY_ENV=production"


def get(url, timeout=3):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read()


assert os.path.isfile("/home/user/configure.py"), "configure.py does not exist"
assert os.path.isfile("/home/user/proxy.py"), "proxy.py does not exist"
assert os.path.isfile("/home/user/launch.sh"), "launch.sh does not exist"
assert os.access("/home/user/launch.sh", os.X_OK), "launch.sh is not executable"
assert subprocess.run(["cmp", "-s", "/home/user/app/app.py", "/tmp/expected_app.py"]).returncode == 0, \
    "/home/user/app/app.py was modified"

# Exercise configure.py against unpredictable existing data, twice.
canary = secrets.token_hex(16)
initial = {
    "original_key": "do_not_delete",
    "verification_canary": canary,
    "nested": {"keep": [1, True, canary]},
    "proxy_active": False,
    "backend_port": 12345,
}
with open("/home/user/app/config.json", "w") as f:
    json.dump(initial, f)
subprocess.run([sys.executable, "/home/user/configure.py"], check=True, timeout=5)
with open("/home/user/app/config.json") as f:
    first = json.load(f)
assert first["original_key"] == "do_not_delete"
assert first["verification_canary"] == canary
assert first["nested"] == initial["nested"]
assert first.get("proxy_active") is True
assert first.get("backend_port") == 8081
subprocess.run([sys.executable, "/home/user/configure.py"], check=True, timeout=5)
with open("/home/user/app/config.json") as f:
    second = json.load(f)
assert second == first, "configure.py is not idempotent"

# Clear any pre-existing synthetic services and execute launch.sh itself.
kill_port(8000)
kill_port(8081)
subprocess.Popen(["/home/user/launch.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True)
wait_port(8081)
verify_backend_process()
status, body = get("http://127.0.0.1:8081/")
assert status == 200
backend_data = json.loads(body)
assert backend_data.get("status") == "ok"
assert backend_data.get("message") == "Backend operational"
assert backend_data.get("config_loaded") is True

# Replace the backend temporarily with a randomized verifier-controlled server,
# then execute proxy.py and require it to relay the exact unpredictable body.
kill_port(8081)
token = secrets.token_urlsafe(32)
oracle_code = r'''
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
token = sys.argv[1]
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"oracle_token": token, "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("localhost", 8081), H).serve_forever()
'''
oracle = subprocess.Popen([sys.executable, "-c", oracle_code, token],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          start_new_session=True)
wait_port(8081)
subprocess.Popen([sys.executable, "/home/user/proxy.py"],
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True)
wait_port(8000)
proxy_pids = listener_pids(8000)
assert len(proxy_pids) == 1, f"Expected one proxy listener, found {proxy_pids}"
proxy_cmd = read_proc(next(iter(proxy_pids)), "cmdline", True).split(b"\0")
assert any(x.decode(errors="replace") == "/home/user/proxy.py" for x in proxy_cmd if x), \
    f"Port 8000 is not served by proxy.py: {proxy_cmd}"
expected_status, expected_body = get("http://127.0.0.1:8081/")
actual_status, actual_body = get("http://127.0.0.1:8000/")
assert actual_status == expected_status == 200
assert actual_body == expected_body, "proxy.py did not return the backend's exact response body"
assert json.loads(actual_body) == {"oracle_token": token, "path": "/"}

# Restore the required final state using launch.sh and verify the still-running proxy.
kill_port(8081)
subprocess.Popen(["/home/user/launch.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True)
wait_port(8081)
verify_backend_process()
backend_status, backend_body = get("http://127.0.0.1:8081/")
proxy_status, proxy_body = get("http://127.0.0.1:8000/")
assert backend_status == proxy_status == 200
assert proxy_body == backend_body
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import urllib.request
import urllib.error
import pytest

def test_config_json_updated():
    config_path = "/home/user/app/config.json"
    assert os.path.isfile(config_path), f"Configuration file {config_path} does not exist."

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {config_path} is not valid JSON.")

    assert config.get("original_key") == "do_not_delete", "The original key 'original_key' was removed or altered."
    assert config.get("proxy_active") is True, "The key 'proxy_active' is not set to true."
    assert config.get("backend_port") == 8081, "The key 'backend_port' is not set to 8081."

def test_configure_script_exists():
    script_path = "/home/user/configure.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

def test_proxy_script_exists():
    script_path = "/home/user/proxy.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

def test_proxy_test_log():
    log_path = "/home/user/proxy_test.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {log_path} is not valid JSON: {content}")

    assert data.get("status") == "ok", "Expected status 'ok' in response."
    assert data.get("message") == "Backend operational", "Expected message 'Backend operational' in response."
    assert data.get("config_loaded") is True, "Expected config_loaded to be true in response."

def test_backend_running():
    try:
        req = urllib.request.Request("http://localhost:8081/")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Backend returned status {response.status}"
            data = json.loads(response.read().decode())
            assert data.get("status") == "ok", "Backend response JSON missing 'status': 'ok'"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to backend on port 8081: {e}")

def test_proxy_running():
    try:
        req = urllib.request.Request("http://localhost:8000/")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Proxy returned status {response.status}"
            data = json.loads(response.read().decode())
            assert data.get("status") == "ok", "Proxy response JSON missing 'status': 'ok'"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to proxy on port 8000: {e}")
TEST_EOF

if python3 /tmp/verify_artifacts.py && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
