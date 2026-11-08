#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

WORKSPACE_DIR = "/home/user/workspace"
VNC_MANAGER_FILE = os.path.join(WORKSPACE_DIR, "vnc_manager.go")
VNC_BINARY = os.path.join(WORKSPACE_DIR, "vnc_manager")
DEPLOY_SCRIPT = os.path.join(WORKSPACE_DIR, "deploy.sh")
DIAGNOSE_FILE = os.path.join(WORKSPACE_DIR, "diagnose.go")
AUDIT_LOG = os.path.join(WORKSPACE_DIR, "audit.log")


def request(url, headers=None, timeout=2):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.headers


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_response(url, headers=None, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return request(url, headers=headers)
        except Exception as error:
            last_error = error
            time.sleep(0.1)
    raise AssertionError(f"Service did not become available at {url}: {last_error}")


def stop_manager():
    subprocess.run(["pkill", "-x", "vnc_manager"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 8080))
            return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("The service on port 8080 did not stop")


def run_deploy(remove_binary=False):
    stop_manager()
    if remove_binary and os.path.exists(VNC_BINARY):
        os.remove(VNC_BINARY)

    env = os.environ.copy()
    env.pop("TZ", None)
    env.pop("VNC_PORT", None)
    result = subprocess.run(
        ["/bin/bash", DEPLOY_SCRIPT], cwd=WORKSPACE_DIR, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"
    assert os.path.isfile(VNC_BINARY), "deploy.sh did not create the vnc_manager executable"
    assert os.access(VNC_BINARY, os.X_OK), "The compiled vnc_manager is not executable"

    status, body, _ = wait_for_response(
        "http://127.0.0.1:8080/status",
        {"X-VNC-Hardening": "Strict"}
    )
    assert status == 200, f"Deployed service returned {status} with the required header"
    assert body == b"VNC Manager Active", f"Unexpected deployed service body: {body!r}"


@pytest.fixture(scope="session")
def deployed_service():
    run_deploy(remove_binary=True)
    try:
        yield
    finally:
        stop_manager()


def test_vnc_manager_patched():
    """Keep the original source-level assertions."""
    assert os.path.isfile(VNC_MANAGER_FILE), f"File {VNC_MANAGER_FILE} does not exist."
    with open(VNC_MANAGER_FILE, "r") as f:
        content = f.read()

    assert "Hardening check failed" in content, "The expected error message 'Hardening check failed' is missing from vnc_manager.go"
    has_403 = "403" in content or "http.StatusForbidden" in content
    assert has_403, "The Go code must return a 403 status code (either as 403 or http.StatusForbidden)."


def test_deploy_script_exists_and_executable():
    """Keep the original deployment-script assertions."""
    assert os.path.isfile(DEPLOY_SCRIPT), f"File {DEPLOY_SCRIPT} does not exist."
    st = os.stat(DEPLOY_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{DEPLOY_SCRIPT} is not executable."

    with open(DEPLOY_SCRIPT, "r") as f:
        content = f.read()

    assert "TZ=Asia/Tokyo" in content or 'export TZ="Asia/Tokyo"' in content or "export TZ=Asia/Tokyo" in content, "deploy.sh does not correctly set TZ=Asia/Tokyo"
    assert "VNC_PORT=8080" in content or 'export VNC_PORT="8080"' in content or "export VNC_PORT=8080" in content, "deploy.sh does not correctly set VNC_PORT=8080"
    assert "vnc_manager.go" in content, "deploy.sh does not seem to compile vnc_manager.go"


def test_vnc_manager_compiles_and_behaves():
    binary = "/tmp/vnc_manager_verified"
    result = subprocess.run(
        ["go", "build", "-o", binary, VNC_MANAGER_FILE],
        cwd=WORKSPACE_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, f"vnc_manager.go does not compile: {result.stderr}"

    port = free_port()
    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    env["VNC_PORT"] = str(port)
    proc = subprocess.Popen([binary], env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    try:
        url = f"http://127.0.0.1:{port}/status"
        status, body, headers = wait_for_response(url)
        assert status == 403, f"Missing hardening header returned HTTP {status}, not 403"
        assert body == b"Hardening check failed", f"Incorrect 403 body: {body!r}"
        assert headers.get_content_type() == "text/plain", "403 response is not plain text"

        status, body, _ = request(url, {"X-VNC-Hardening": "Strict"})
        assert status == 200
        assert body == b"VNC Manager Active"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_deploy_script_actually_builds_and_starts_service(deployed_service):
    status, body, _ = request("http://127.0.0.1:8080/status")
    assert status == 403
    assert body == b"Hardening check failed"


def test_diagnose_script_exists():
    """Keep the original existence assertion."""
    assert os.path.isfile(DIAGNOSE_FILE), f"File {DIAGNOSE_FILE} does not exist."


@pytest.fixture(scope="session")
def verified_diagnostic(deployed_service):
    if os.path.exists(AUDIT_LOG):
        os.remove(AUDIT_LOG)

    first = subprocess.run(
        ["go", "run", DIAGNOSE_FILE], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert first.returncode == 0, f"diagnose.go failed against the service: {first.stderr}"
    assert os.path.isfile(AUDIT_LOG), "diagnose.go did not create audit.log"
    with open(AUDIT_LOG, "r") as f:
        assert f.read().strip() == "Result: 403 - Hardening check failed"

    # Exercise the diagnostic against a verifier-controlled response so a
    # hard-coded audit.log cannot pass.
    stop_manager()
    token = "diagnostic-" + secrets.token_hex(12)
    seen = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            seen["path"] = self.path
            seen["hardening"] = self.headers.get("X-VNC-Hardening")
            payload = token.encode()
            self.send_response(418)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    try:
        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)
        dynamic = subprocess.run(
            ["go", "run", DIAGNOSE_FILE], cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert dynamic.returncode == 0, f"diagnose.go failed: {dynamic.stderr}"
        thread.join(timeout=5)
        assert not thread.is_alive(), "diagnose.go made no request to 127.0.0.1:8080"
    finally:
        server.server_close()

    assert seen.get("path") == "/status", f"diagnose.go requested {seen.get('path')!r}, not /status"
    assert seen.get("hardening") is None, "diagnose.go must omit X-VNC-Hardening"
    assert os.path.isfile(AUDIT_LOG), "diagnose.go did not recreate audit.log"
    with open(AUDIT_LOG, "r") as f:
        dynamic_log = f.read().strip()
    assert dynamic_log == f"Result: 418 - {token}", f"Diagnostic output was not derived from the HTTP response: {dynamic_log!r}"

    # Restore the required deployed state and required final audit result.
    run_deploy(remove_binary=False)
    os.remove(AUDIT_LOG)
    final = subprocess.run(
        ["go", "run", DIAGNOSE_FILE], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert final.returncode == 0, f"Final diagnostic run failed: {final.stderr}"
    yield


def test_diagnostic_tool_executes(verified_diagnostic):
    assert os.path.isfile(AUDIT_LOG)


def test_audit_log_content(verified_diagnostic):
    """Keep the original audit-log assertion and strengthen it to exact output."""
    assert os.path.isfile(AUDIT_LOG), f"File {AUDIT_LOG} does not exist. Did the diagnostic tool run successfully?"
    with open(AUDIT_LOG, "r") as f:
        content = f.read().strip()

    expected_content = "Result: 403 - Hardening check failed"
    assert content.startswith("Result: 403 - Hardening check failed"), f"audit.log content is incorrect. Expected to start with '{expected_content}', got '{content}'"
    assert content == expected_content, f"audit.log has unexpected extra content: {content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
