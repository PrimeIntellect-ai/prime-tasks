#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import uuid

import pytest


def run_as_user(script_path, timeout=15):
    try:
        return subprocess.run(
            ["su", "-", "user", "-c", f"python3 {script_path}"],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {script_path} failed.\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {script_path} timed out. Are the background processes hanging?")


def stop_services():
    subprocess.run(
        ["pkill", "-u", "user", "-f", "/home/user/app/(backend|proxy)\\.py"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.3)


def assert_process_gone(pid):
    deadline = time.time() + 2
    while time.time() < deadline and os.path.exists(f"/proc/{pid}"):
        time.sleep(0.05)
    assert not os.path.exists(f"/proc/{pid}"), f"Service process {pid} was not cleaned up."


def test_profile_fixed():
    profile_path = "/home/user/.profile"
    assert os.path.isfile(profile_path), f"{profile_path} is missing."

    with open(profile_path, "r") as f:
        content = f.read()

    assert "export APP_SOCK=" in content, "APP_SOCK environment variable is not exported in .profile."
    assert "export APP_SOC=" not in content, "The typo (APP_SOC) in .profile was not removed."

    result = subprocess.run(
        ["su", "-", "user", "-c", ". /home/user/.profile; printf '%s' \"$APP_SOCK\""],
        check=True,
        capture_output=True,
        text=True,
    )
    assert result.stdout == "/home/user/run/app.sock", \
        f"Sourcing .profile set APP_SOCK to {result.stdout!r}, not '/home/user/run/app.sock'."


def test_backend_fixed_and_functional():
    backend_path = "/home/user/app/backend.py"
    assert os.path.isfile(backend_path), f"{backend_path} is missing."

    with open(backend_path, "r") as f:
        content = f.read()

    # Retain the original source-level assertion.
    has_dir_creation = any(keyword in content for keyword in ["os.makedirs", "os.mkdir", "mkdir", "Path"])
    assert has_dir_creation, "backend.py does not appear to contain directory creation logic."

    base = tempfile.mkdtemp(prefix="backend-check-", dir="/tmp")
    os.chmod(base, 0o777)
    sock_path = os.path.join(base, "one", "two", "app.sock")
    env = os.environ.copy()
    env["APP_SOCK"] = sock_path
    proc = subprocess.Popen(
        ["su", "-s", "/bin/bash", "user", "-c", "exec python3 /home/user/app/backend.py"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(sock_path) and proc.poll() is None:
            time.sleep(0.05)
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(f"backend.py exited before binding the configured socket.\nSTDOUT: {out}\nSTDERR: {err}")
        assert os.path.isdir(os.path.dirname(sock_path)), "backend.py did not create nested parent directories."
        assert stat_is_socket(sock_path), "backend.py did not bind a Unix socket at APP_SOCK."

        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(2)
        client.connect(sock_path)
        client.sendall(b"GET / HTTP/1.0\r\n\r\n")
        response = client.recv(4096)
        client.close()
        assert b"Backend Operational" in response, "backend.py did not serve the expected response."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        shutil.rmtree(base, ignore_errors=True)


def stat_is_socket(path):
    import stat
    try:
        return stat.S_ISSOCK(os.stat(path).st_mode)
    except FileNotFoundError:
        return False


def test_verify_deploy_script_orchestrates_services_and_results():
    script_path = "/home/user/verify_deploy.py"
    assert os.path.isfile(script_path), f"{script_path} is missing. Did you create the verification script?"

    backend_path = "/home/user/app/backend.py"
    proxy_path = "/home/user/app/proxy.py"
    token = uuid.uuid4().hex
    backend_events = f"/tmp/backend-events-{token}.jsonl"
    proxy_events = f"/tmp/proxy-events-{token}.jsonl"
    backend_backup = f"/tmp/backend-{token}.bak"
    proxy_backup = f"/tmp/proxy-{token}.bak"

    backend_probe = f'''import json, os, signal, sys, time
EVENTS = {backend_events!r}
def event(kind):
    with open(EVENTS, "a") as f:
        f.write(json.dumps({{"kind": kind, "pid": os.getpid(), "time": time.time(), "APP_SOCK": os.environ.get("APP_SOCK")}}) + "\\n")
def stop(signum, frame):
    event("stopped")
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
event("started")
while True:
    time.sleep(0.1)
'''

    proxy_probe = f'''import json, os, signal, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
EVENTS = {proxy_events!r}
def event(kind, **extra):
    data = {{"kind": kind, "pid": os.getpid(), "time": time.time()}}
    data.update(extra)
    with open(EVENTS, "a") as f:
        f.write(json.dumps(data) + "\\n")
def stop(signum, frame):
    event("stopped")
    sys.exit(0)
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        event("get", path=self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Backend Operational")
    def log_message(self, *args):
        pass
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
server = HTTPServer(("127.0.0.1", 8080), Handler)
event("started")
try:
    server.serve_forever()
finally:
    server.server_close()
'''

    stop_services()
    shutil.copy2(backend_path, backend_backup)
    shutil.copy2(proxy_path, proxy_backup)
    try:
        with open(backend_path, "w") as f:
            f.write(backend_probe)
        with open(proxy_path, "w") as f:
            f.write(proxy_probe)
        os.chown(backend_path, 1000, 1000)
        os.chown(proxy_path, 1000, 1000)
        os.chmod(backend_path, 0o755)
        os.chmod(proxy_path, 0o755)

        start = time.time()
        run_as_user(script_path)

        with open(backend_events) as f:
            backend_data = [json.loads(line) for line in f if line.strip()]
        with open(proxy_events) as f:
            proxy_data = [json.loads(line) for line in f if line.strip()]

        backend_started = next((e for e in backend_data if e["kind"] == "started"), None)
        proxy_started = next((e for e in proxy_data if e["kind"] == "started"), None)
        get_event = next((e for e in proxy_data if e["kind"] == "get"), None)
        assert backend_started is not None, "verify_deploy.py did not start backend.py."
        assert proxy_started is not None, "verify_deploy.py did not start proxy.py."
        assert backend_started["APP_SOCK"] == "/home/user/run/app.sock", \
            "verify_deploy.py did not source .profile before starting the backend."
        assert get_event is not None and get_event.get("path") == "/", \
            "verify_deploy.py did not make an HTTP GET request to the proxy root URL."
        assert get_event["time"] - max(backend_started["time"], proxy_started["time"]) >= 1.7, \
            "verify_deploy.py did not wait approximately 2 seconds before its HTTP request."
        assert any(e["kind"] == "stopped" for e in backend_data), "verify_deploy.py did not terminate the backend."
        assert any(e["kind"] == "stopped" for e in proxy_data), "verify_deploy.py did not terminate the proxy."
        assert_process_gone(backend_started["pid"])
        assert_process_gone(proxy_started["pid"])

        log_path = "/home/user/deploy_results.log"
        assert os.path.isfile(log_path), f"The log file {log_path} was not created."
        with open(log_path) as f:
            log_content = f.read().strip()
        expected_content = "STATUS: 200 | BODY: Backend Operational"
        assert log_content == expected_content, f"Log file content is incorrect.\nExpected: '{expected_content}'\nGot: '{log_content}'"
        assert time.time() - start < 15
    finally:
        stop_services()
        shutil.move(backend_backup, backend_path)
        shutil.move(proxy_backup, proxy_path)
        for path in (backend_events, proxy_events):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Run the submitted script once more against the real services, from a clean state.
    stop_services()
    shutil.rmtree("/home/user/run", ignore_errors=True)
    try:
        os.remove("/home/user/deploy_results.log")
    except FileNotFoundError:
        pass

    run_as_user(script_path)

    run_dir = "/home/user/run"
    assert os.path.isdir(run_dir), f"The directory {run_dir} was not created by the backend script."
    assert os.path.exists("/home/user/run/app.sock"), "The backend socket was not created at the configured path."

    log_path = "/home/user/deploy_results.log"
    assert os.path.isfile(log_path), f"The log file {log_path} was not created."
    with open(log_path, "r") as f:
        log_content = f.read().strip()
    expected_content = "STATUS: 200 | BODY: Backend Operational"
    assert log_content == expected_content, f"Log file content is incorrect.\nExpected: '{expected_content}'\nGot: '{log_content}'"
    stop_services()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
