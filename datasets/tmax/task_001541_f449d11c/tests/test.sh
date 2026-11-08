#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import importlib.util
import json
import os
import re
import signal
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

REPORT_PATH = "/home/user/audit_report.json"
FIXED_APP_PATH = "/home/user/api/fixed_app.py"
LOG_PATH = "/home/user/api/server.log"
SECRET = "FLAG_SECURE_JWT_DATA_9921"


def b64json(value):
    return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode().rstrip("=")


def candidate_scripts():
    excluded = {
        os.path.realpath("/home/user/api/app.py"),
        os.path.realpath(FIXED_APP_PATH),
    }
    found = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not d.startswith(".")]
        for name in files:
            path = os.path.realpath(os.path.join(root, name))
            if name.endswith(".py") and path not in excluded:
                found.append(path)
    return sorted(set(found))


def stop_processes_listening_on_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGKILL)
                    break
        except (OSError, ProcessLookupError):
            pass


class ExploitHandler(BaseHTTPRequestHandler):
    successful_tokens = []

    def do_GET(self):
        status = 403
        body = {"error": "Unauthorized"}
        auth = self.headers.get("Authorization", "")
        if self.path == "/admin/data" and auth.startswith("Bearer "):
            token = auth[7:]
            try:
                parts = token.split(".")
                assert len(parts) == 3
                header = json.loads(base64.urlsafe_b64decode(parts[0] + "=" * (-len(parts[0]) % 4)))
                payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
                if header.get("alg", "").lower() == "none" and payload.get("role") == "admin" and parts[2] == "":
                    type(self).successful_tokens.append(token)
                    status = 200
                    body = {"data": SECRET}
            except Exception:
                pass
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope="module")
def exploit_server():
    stop_processes_listening_on_8080()
    server = ThreadingHTTPServer(("127.0.0.1", 8080), ExploitHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()


def run_script(path, timeout=12):
    try:
        return subprocess.run(
            ["python3", path],
            cwd=os.path.dirname(path) or "/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            env=os.environ.copy(),
        )
    except (subprocess.TimeoutExpired, OSError):
        return None


def test_audit_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert isinstance(data, dict), "The JSON root should be a dictionary."
    assert set(data) == {"cwe_id", "admin_secret", "malicious_ips"}, "The report must exactly use the requested structure."


def test_audit_report_cwe_id():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert data.get("cwe_id") == "CWE-347", "The specific signature-verification weakness is CWE-347."


def test_audit_report_admin_secret():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert data.get("admin_secret") == SECRET


def test_audit_report_malicious_ips():
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert data.get("malicious_ips") == ["10.0.0.5", "172.16.0.4"], "malicious_ips must be complete and sorted."


def test_exploitation_script_exists_and_actually_exploits(exploit_server):
    scripts = candidate_scripts()
    assert scripts, "No exploitation or log-analysis Python scripts were created."
    original_report = open(REPORT_PATH, "rb").read()
    successful = []
    try:
        for path in scripts:
            ExploitHandler.successful_tokens.clear()
            result = run_script(path)
            if result is not None and result.returncode == 0 and ExploitHandler.successful_tokens:
                successful.append(path)
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
    finally:
        with open(REPORT_PATH, "wb") as f:
            f.write(original_report)
    assert successful, "No submitted Python script forged an unsigned admin JWT and requested /admin/data."
    pytest.exploit_scripts = set(successful)


def test_log_analysis_script_exists_and_handles_derived_logs(exploit_server):
    scripts = candidate_scripts()
    original_log = open(LOG_PATH, "rb").read()
    original_report = open(REPORT_PATH, "rb").read()

    nonce = os.urandom(3).hex()
    expected = [f"10.31.{int(nonce[:2], 16)}.{int(nonce[2:4], 16)}", f"172.29.{int(nonce[4:6], 16)}.77"]
    expected = sorted(expected, key=lambda ip: tuple(map(int, ip.split("."))))
    benign = "192.0.2.199"
    none_token = b64json({"alg": "none", "typ": "JWT"}) + "." + b64json({"role": "admin"}) + "."
    upper_none_token = b64json({"alg": "NONE", "typ": "JWT"}) + "." + b64json({"role": "admin"}) + "."
    hs_token = b64json({"alg": "HS256", "typ": "JWT"}) + "." + b64json({"role": "user"}) + ".invalid"
    synthetic = (
        f'{expected[0]} - - [11/Sep/2026:01:00:00 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer {none_token}" "test"\n'
        f'{benign} - - [11/Sep/2026:01:00:01 +0000] "GET /admin/data HTTP/1.1" 403 - "Bearer {hs_token}" "test"\n'
        f'{expected[1]} - - [11/Sep/2026:01:00:02 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer {upper_none_token}" "test"\n'
        f'{expected[0]} - - [11/Sep/2026:01:00:03 +0000] "GET /admin/data HTTP/1.1" 200 - "Bearer {none_token}" "test"\n'
    )

    successful = []
    try:
        with open(LOG_PATH, "w") as f:
            f.write(synthetic)
        for path in scripts:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
            result = run_script(path)
            if result is None or result.returncode != 0:
                continue
            observed = set(re.findall(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", result.stdout + "\n" + result.stderr))
            try:
                with open(REPORT_PATH) as f:
                    generated = json.load(f)
                if isinstance(generated.get("malicious_ips"), list):
                    observed.update(generated["malicious_ips"])
            except Exception:
                pass
            if set(expected).issubset(observed) and benign not in observed:
                successful.append(path)
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        with open(REPORT_PATH, "wb") as f:
            f.write(original_report)

    assert successful, "No submitted Python script correctly detected alg=none attacks in derived access logs."
    exploit_scripts = getattr(pytest, "exploit_scripts", set())
    assert any(e != a for e in exploit_scripts for a in successful), "Create separate exploitation and log-analysis Python scripts as requested."


def test_fixed_app_exists_and_patched():
    assert os.path.isfile(FIXED_APP_PATH), f"Patched application file {FIXED_APP_PATH} is missing."
    with open(FIXED_APP_PATH) as f:
        content = f.read()

    vulnerable_pattern = re.compile(r"alg\s*==\s*['\"]none['\"]", re.IGNORECASE)
    assert not vulnerable_pattern.search(content), "The fixed_app.py still appears to contain the alg=none bypass."
    assert "hs256" in content.lower(), "The fixed_app.py must explicitly enforce the HS256 algorithm."

    spec = importlib.util.spec_from_file_location("submitted_fixed_app", FIXED_APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "fixed_app.py must provide a runnable Flask application."

    key = getattr(module, "SECRET_KEY", b"super_secret_key_12345")
    if isinstance(key, str):
        key = key.encode()

    def make_token(alg, role="admin", valid_signature=False):
        header = b64json({"alg": alg, "typ": "JWT"})
        payload = b64json({"user": "auditor", "role": role})
        signature = ""
        if valid_signature:
            signature = base64.urlsafe_b64encode(hmac.new(key, f"{header}.{payload}".encode(), hashlib.sha256).digest()).decode().rstrip("=")
        return f"{header}.{payload}.{signature}"

    client = module.app.test_client()
    for token in (make_token("none"), make_token("NONE"), make_token("hs256", valid_signature=True), make_token("HS256")):
        response = client.get("/admin/data", headers={"Authorization": "Bearer " + token})
        assert response.status_code in (401, 403), "fixed_app.py accepted an unsigned, invalidly signed, or non-exact-algorithm token."

    valid = make_token("HS256", valid_signature=True)
    response = client.get("/admin/data", headers={"Authorization": "Bearer " + valid})
    assert response.status_code == 200, "fixed_app.py must continue accepting correctly signed HS256 admin tokens."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
