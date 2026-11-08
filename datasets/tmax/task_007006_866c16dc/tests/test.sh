#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import json
import os
import runpy
import socket
import stat
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

APP_DIR = "/home/user/app"
USERS_JSON = os.path.join(APP_DIR, "users.json")
AUTH_SERVICE = os.path.join(APP_DIR, "auth_service.py")
DATA_SERVICE = os.path.join(APP_DIR, "data_service.py")
PIPELINE_SCRIPT = "/home/user/run_pipeline.sh"
BUILD_RESULT = "/home/user/build_result.txt"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def wait_for_port(port, proc=None, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail(f"Service for port {port} exited with code {proc.returncode}")
        try:
            with socket.create_connection(("localhost", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"Service did not start listening on port {port}")


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_users_json_fixed():
    assert os.path.isfile(USERS_JSON), f"{USERS_JSON} is missing."
    try:
        with open(USERS_JSON, 'r') as f:
            users = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{USERS_JSON} is not valid JSON. Syntax error was not fixed.")

    assert "ci_worker" in users, "User 'ci_worker' is missing from users.json."
    ci_worker = users["ci_worker"]
    assert ci_worker.get("password") == "ci_secure_pass", "Incorrect password for 'ci_worker'."
    assert ci_worker.get("role") == "builder", "Incorrect role for 'ci_worker'."


def test_auth_service_communication_fixed():
    assert os.path.isfile(AUTH_SERVICE), f"{AUTH_SERVICE} is missing."
    with open(AUTH_SERVICE, 'r') as f:
        content = f.read()

    assert "X-Internal-User" in content, "auth_service.py is not using 'X-Internal-User' header."
    assert "X-Forwarded-User" not in content, "auth_service.py is still using 'X-Forwarded-User' header."


def test_auth_service_log_rotation_configured():
    assert os.path.isfile(AUTH_SERVICE), f"{AUTH_SERVICE} is missing."
    with open(AUTH_SERVICE, 'r') as f:
        content = f.read()

    assert "TimedRotatingFileHandler" in content, "TimedRotatingFileHandler not found in auth_service.py."
    assert "midnight" in content or "'midnight'" in content or '"midnight"' in content, "Log rotation when='midnight' not found."
    assert "backupCount=5" in content.replace(" ", ""), "Log rotation backupCount=5 not found."


def test_log_rotation_is_active_and_functional():
    for path in glob.glob("/home/user/app/logs/auth.log.*"):
        os.remove(path)

    probe = r'''
import glob
import json
import logging
import logging.handlers
import os
import runpy

runpy.run_path("/home/user/app/auth_service.py", run_name="verifier_import")
handlers = logging.getLogger().handlers
timed = [h for h in handlers if isinstance(h, logging.handlers.TimedRotatingFileHandler)]
plain = [h for h in handlers if type(h) is logging.FileHandler]
assert timed, "No active TimedRotatingFileHandler is configured"
assert not plain, "A standard FileHandler is still active"
h = timed[0]
assert os.path.realpath(h.baseFilename) == os.path.realpath("/home/user/app/logs/auth.log")
assert h.when == "MIDNIGHT"
assert h.backupCount == 5
marker = "rotation-probe-marker"
h.emit(logging.LogRecord("probe", logging.INFO, __file__, 1, marker, (), None))
h.flush()
h.doRollover()
h.emit(logging.LogRecord("probe", logging.INFO, __file__, 1, "after-rollover", (), None))
h.flush()
backups = glob.glob("/home/user/app/logs/auth.log.*")
assert backups, "Forced rollover did not create a rotated log"
assert any(marker in open(p, errors="replace").read() for p in backups)
print(json.dumps({"ok": True}))
'''
    result = subprocess.run(["python3", "-c", probe], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr or result.stdout
    assert json.loads(result.stdout.strip().splitlines()[-1])["ok"] is True


def test_auth_service_really_forwards_internal_header():
    observed = {}
    response_body = ("backend-" + uuid.uuid4().hex).encode()

    class BackendHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            observed["path"] = self.path
            observed["internal"] = self.headers.get("X-Internal-User")
            observed["forwarded"] = self.headers.get("X-Forwarded-User")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(response_body)

        def log_message(self, *args):
            pass

    backend = ReusableHTTPServer(("localhost", 8082), BackendHandler)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    auth_proc = subprocess.Popen(["python3", AUTH_SERVICE], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        wait_for_port(8081, auth_proc)
        conn = http.client.HTTPConnection("localhost", 8081, timeout=3)
        payload = json.dumps({"username": "ci_worker", "password": "ci_secure_pass"})
        conn.request("POST", "/login", body=payload, headers={"Content-Type": "application/json"})
        login = conn.getresponse()
        login_body = login.read()
        assert login.status == 200, login_body
        token = json.loads(login_body)["token"]
        conn.close()

        conn = http.client.HTTPConnection("localhost", 8081, timeout=3)
        conn.request("POST", "/trigger", body=b"", headers={"Authorization": "Bearer " + token})
        trigger = conn.getresponse()
        body = trigger.read()
        conn.close()
        assert trigger.status == 200
        assert body == response_body
        assert observed.get("path") == "/build"
        assert observed.get("internal") == "ci_worker"
        assert observed.get("forwarded") is None
    finally:
        stop_process(auth_proc)
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(PIPELINE_SCRIPT), f"{PIPELINE_SCRIPT} is missing."
    st = os.stat(PIPELINE_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE_SCRIPT} is not executable."


def test_pipeline_performs_login_and_authenticated_trigger():
    token = "verify-token-" + uuid.uuid4().hex
    raw_trigger_body = ("  {\n  \"status\": \"success\", \"nonce\": \"" + uuid.uuid4().hex + "\"\n}\n").encode()
    calls = []

    class PipelineHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            calls.append((self.path, dict(self.headers), body))
            if self.path == "/login":
                try:
                    data = json.loads(body)
                except Exception:
                    self.send_response(400)
                    self.end_headers()
                    return
                if data != {"username": "ci_worker", "password": "ci_secure_pass"}:
                    self.send_response(403)
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"token": token}).encode())
            elif self.path == "/trigger":
                if self.headers.get("Authorization") != "Bearer " + token:
                    self.send_response(401)
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(raw_trigger_body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *args):
            pass

    server = ReusableHTTPServer(("localhost", 8081), PipelineHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.exists(BUILD_RESULT):
            os.remove(BUILD_RESULT)
        result = subprocess.run([PIPELINE_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr or result.stdout
        assert [c[0] for c in calls] == ["/login", "/trigger"], "Pipeline must login and then trigger through port 8081"
        assert os.path.isfile(BUILD_RESULT), f"{BUILD_RESULT} was not created by the pipeline script."
        with open(BUILD_RESULT, "rb") as f:
            assert f.read() == raw_trigger_body, "build_result.txt must contain the raw /trigger response body"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_pipeline_execution():
    # Remove result file if it exists
    if os.path.exists(BUILD_RESULT):
        os.remove(BUILD_RESULT)

    # Start services
    auth_proc = subprocess.Popen(["python3", AUTH_SERVICE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    data_proc = subprocess.Popen(["python3", DATA_SERVICE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        # Give services a moment to start
        wait_for_port(8081, auth_proc)
        wait_for_port(8082, data_proc)

        # Run pipeline script
        result = subprocess.run([PIPELINE_SCRIPT], capture_output=True, text=True)
        assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}"

        # Check result file
        assert os.path.isfile(BUILD_RESULT), f"{BUILD_RESULT} was not created by the pipeline script."
        with open(BUILD_RESULT, 'r') as f:
            result_content = f.read().strip()

        try:
            result_json = json.loads(result_content)
        except json.JSONDecodeError:
            pytest.fail(f"Content of {BUILD_RESULT} is not valid JSON: {result_content}")

        assert result_json.get("status") == "success", f"Expected status 'success', got {result_json.get('status')}"
        assert result_json.get("build_id") == "build_for_ci_worker", f"Expected build_id 'build_for_ci_worker', got {result_json.get('build_id')}"

    finally:
        # Cleanup processes
        stop_process(auth_proc)
        stop_process(data_proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
