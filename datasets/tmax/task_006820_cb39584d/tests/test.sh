#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

SCRIPT_PATH = "/home/user/verify_auth.sh"
RESULT_PATH = "/home/user/verification_result.log"
ACCESS_LOG = "/home/user/app/logs/access.log"
CAPTURE_PATH = "/tmp/verifier_curl_capture.jsonl"
REAL_CURL = "/tmp/verifier_real_curl"
SYSTEM_CURL = "/usr/bin/curl"


def test_verify_auth_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_verify_auth_script_contains_env_i():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "env -i" in content, f"Script {SCRIPT_PATH} does not contain 'env -i' as required for process isolation."


def test_verification_result_log():
    assert os.path.isfile(RESULT_PATH), f"Result log {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {RESULT_PATH} is not valid JSON. Found: {content}")
    assert data.get("authenticated") is True, f'Expected {{"authenticated": true}} in {RESULT_PATH}, but got {content}'


def request_body(token):
    req = urllib.request.Request(
        "http://127.0.0.1:9090/api/verify",
        headers={"Authorization": f"Bearer {token}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def read_capture():
    assert os.path.isfile(CAPTURE_PATH), "verify_auth.sh did not execute the system curl command"
    records = []
    with open(CAPTURE_PATH, "r", encoding="utf-8") as capture:
        for line in capture:
            if line.strip():
                records.append(json.loads(line))
    assert records, "verify_auth.sh did not execute curl"
    return records


def verify_curl_record(records):
    matching = [r for r in records if "http://127.0.0.1:9090/api/verify" in r["args"]]
    assert matching, "curl was not used to request the required verify endpoint"
    record = matching[-1]
    assert record["cwd"] == "/tmp", f"curl ran from {record['cwd']!r}, not /tmp"
    for key in ("VERIFIER_ENV_CANARY", "HOME", "USER", "LOGNAME"):
        assert key not in record["env"], f"curl inherited {key}; it was not run in a cleared environment"
    joined = " ".join(record["args"])
    match = re.search(r"Authorization\s*:\s*Bearer\s+([0-9a-f]{32})(?:\s|$)", joined)
    assert match, "curl did not receive an Authorization: Bearer header with a lowercase hexadecimal token"
    return match.group(1)


def stop_original_server():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read()
            if b"mock_auth_server.py" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            probe = HTTPServer(("127.0.0.1", 9090), BaseHTTPRequestHandler)
            probe.server_close()
            return
        except OSError:
            time.sleep(0.1)
    pytest.fail("Could not stop the original authentication server")


def test_real_rotation_and_isolated_script_behavior():
    with open(ACCESS_LOG, "r", encoding="utf-8") as f:
        leaked_match = re.search(r"Bearer ([A-Za-z0-9]{32})", f.read())
    assert leaked_match, "Could not derive the leaked token from access.log"
    leaked_token = leaked_match.group(1)

    assert os.path.isfile(SYSTEM_CURL), "System curl is unavailable"
    if os.path.exists(REAL_CURL):
        os.unlink(REAL_CURL)
    os.rename(SYSTEM_CURL, REAL_CURL)
    wrapper = '''#!/bin/sh
/usr/bin/python3 - "$@" <<'PY'
import json, os, sys
with open("/tmp/verifier_curl_capture.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"cwd": os.getcwd(), "env": dict(os.environ), "args": sys.argv[1:]}) + "\\n")
PY
exec /tmp/verifier_real_curl "$@"
'''
    with open(SYSTEM_CURL, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(SYSTEM_CURL, 0o755)

    custom_server = None
    try:
        if os.path.exists(CAPTURE_PATH):
            os.unlink(CAPTURE_PATH)
        if os.path.exists(RESULT_PATH):
            os.unlink(RESULT_PATH)

        run_env = os.environ.copy()
        run_env.update({
            "VERIFIER_ENV_CANARY": "must-not-reach-curl",
            "HOME": "/definitely/not/the/real/home",
            "USER": "environment-canary-user",
            "LOGNAME": "environment-canary-logname",
        })
        completed = subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", env=run_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )
        assert completed.returncode == 0, f"verify_auth.sh failed: {completed.stderr.decode(errors='replace')}"

        new_token = verify_curl_record(read_capture())
        assert new_token != leaked_token, "The leaked token was not replaced"
        assert re.fullmatch(r"[0-9a-f]{32}", new_token), "The new token is not 32-character lowercase hex"

        new_status, new_body = request_body(new_token)
        old_status, old_body = request_body(leaked_token)
        random_status, random_body = request_body(secrets.token_hex(16))
        assert new_status == 200 and json.loads(new_body).get("authenticated") is True, "The authentication service does not accept the new token"
        assert old_status == 401 and json.loads(old_body).get("authenticated") is False, "The leaked token is still active"
        assert random_status == 401 and json.loads(random_body).get("authenticated") is False, "The service accepts an unrelated token"
        with open(RESULT_PATH, "rb") as f:
            assert f.read() == new_body, "verification_result.log is not the exact response body returned by the service"

        stop_original_server()
        nonce_body = json.dumps({"authenticated": True, "nonce": secrets.token_hex(16)}, separators=(",", ":")).encode()
        seen = []

        class ChallengeHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append((self.path, self.headers.get("Authorization")))
                if self.path == "/api/verify" and self.headers.get("Authorization") == f"Bearer {new_token}":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(nonce_body)
                else:
                    self.send_response(401)
                    self.end_headers()
                    self.wfile.write(b'{"authenticated":false}')
            def log_message(self, format, *args):
                pass

        custom_server = HTTPServer(("127.0.0.1", 9090), ChallengeHandler)
        thread = threading.Thread(target=custom_server.serve_forever, daemon=True)
        thread.start()
        open(CAPTURE_PATH, "w").close()
        if os.path.exists(RESULT_PATH):
            os.unlink(RESULT_PATH)
        completed = subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", env=run_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )
        assert completed.returncode == 0, f"verify_auth.sh failed against the challenge endpoint: {completed.stderr.decode(errors='replace')}"
        assert ("/api/verify", f"Bearer {new_token}") in seen, "The script did not send the required authenticated GET request"
        verify_curl_record(read_capture())
        with open(RESULT_PATH, "rb") as f:
            assert f.read() == nonce_body, "The script did not write the exact live HTTP response body"
    finally:
        if custom_server is not None:
            custom_server.shutdown()
            custom_server.server_close()
        if os.path.exists(SYSTEM_CURL):
            os.unlink(SYSTEM_CURL)
        if os.path.exists(REAL_CURL):
            os.rename(REAL_CURL, SYSTEM_CURL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
