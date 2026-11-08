#!/bin/bash
set +e
mkdir -p /logs/verifier
MOCK_PID=""

run_checks() {
    # The task explicitly requires the agent to start the supplied server.
    python3 - <<'PY' || return 1
import json
import urllib.request

req = urllib.request.Request(
    "http://127.0.0.1:8080/api/login",
    data=json.dumps({"username": "admin", "password": "password123"}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=3) as response:
    assert response.status == 200
    assert "session_id=" in response.headers.get("Set-Cookie", "")
PY

    # Preserve the original final-state assertions.
    cat <<'TEST_EOF' > /tmp/test_original_report.py
import os
import json

def test_compliance_report_exists_and_correct():
    report_path = "/home/user/compliance_report.json"

    assert os.path.isfile(report_path), f"Compliance report not found at {report_path}."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {report_path} is not valid JSON."

    expected_keys = {"cookie_security", "missing_security_headers", "redacted_users"}
    assert set(report.keys()) == expected_keys, f"Report keys do not match. Expected {expected_keys}, got {set(report.keys())}."

    cookie_sec = report["cookie_security"]
    assert cookie_sec.get("has_httponly") is True, "Expected 'has_httponly' to be True."
    assert cookie_sec.get("has_secure") is False, "Expected 'has_secure' to be False."

    missing_headers = report["missing_security_headers"]
    expected_missing_headers = ["Content-Security-Policy", "Strict-Transport-Security"]
    assert isinstance(missing_headers, list), "'missing_security_headers' should be a list."
    assert sorted(missing_headers) == expected_missing_headers, f"Expected missing headers {expected_missing_headers}, got {missing_headers}."

    redacted_users = report["redacted_users"]
    assert isinstance(redacted_users, list), "'redacted_users' should be a list."
    assert len(redacted_users) == 2, f"Expected 2 redacted users, got {len(redacted_users)}."

    expected_users = [
        {"name": "Alice Smith", "ssn": "***-**-****", "role": "Manager"},
        {"name": "Bob Jones", "ssn": "***-**-****", "role": "Developer"}
    ]

    redacted_users_sorted = sorted(redacted_users, key=lambda x: x.get("name", ""))
    expected_users_sorted = sorted(expected_users, key=lambda x: x.get("name", ""))
    assert redacted_users_sorted == expected_users_sorted, f"Redacted users do not match expected output. Got {redacted_users}."
TEST_EOF
    python3 -m pytest /tmp/test_original_report.py -x --tb=short || return 1

    test -f /home/user/policy_tester.py || return 1

    # Stop the original background server so the submitted tester can be
    # exercised against a fresh, unpredictable API with the same contract.
    pkill -f '[p]ython[^ ]* .*server.py' 2>/dev/null || true
    pkill -f '[p]ython3 server.py' 2>/dev/null || true
    sleep 1

    rm -f /tmp/policy_dynamic_expected.json /tmp/policy_dynamic_events.jsonl

    cat <<'PY' > /tmp/policy_mock_server.py
import json
import random
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

required = [
    "Strict-Transport-Security",
    "Content-Security-Policy",
    "X-Frame-Options",
    "X-Content-Type-Options",
]
original_missing = ["Content-Security-Policy", "Strict-Transport-Security"]
while True:
    present = {h for h in required if random.choice((True, False))}
    missing = sorted(h for h in required if h not in present)
    if missing != original_missing:
        break

httponly = random.choice((True, False))
token = secrets.token_urlsafe(18)
suffix = secrets.token_hex(4)
users = [
    {"name": "Aster " + suffix, "ssn": "314-15-9265", "role": "Auditor"},
    {"name": "Birch " + suffix, "ssn": "271-82-8182", "role": "Engineer"},
    {"name": "Cedar " + suffix, "ssn": "161-80-3398", "role": "Analyst"},
]
expected = {
    "cookie_security": {"has_httponly": httponly, "has_secure": False},
    "missing_security_headers": missing,
    "redacted_users": [dict(u, ssn="***-**-****") for u in users],
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def event(self, kind):
        with open("/tmp/policy_dynamic_events.jsonl", "a") as f:
            f.write(json.dumps({"event": kind}) + "\n")

    def send_json(self, status, value, headers=None):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, val in (headers or []):
            self.send_header(key, val)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw)
        except Exception:
            payload = None
        if (self.path == "/api/login" and
                self.headers.get_content_type() == "application/json" and
                payload == {"username": "admin", "password": "password123"}):
            cookie = "session_id=" + token + "; Path=/"
            if httponly:
                cookie += "; HttpOnly"
            response_headers = [("Set-Cookie", cookie)]
            response_headers.extend((h, "dynamic-value") for h in present)
            self.event("valid_login")
            self.send_json(200, {"message": "Logged in"}, response_headers)
        else:
            self.event("invalid_login")
            self.send_json(401, {"error": "Unauthorized"})

    def do_GET(self):
        cookies = self.headers.get("Cookie", "")
        valid_cookie = any(
            part.strip() == "session_id=" + token for part in cookies.split(";")
        )
        if self.path == "/api/users" and valid_cookie:
            self.event("authorized_users")
            self.send_json(200, users)
        else:
            self.event("unauthorized_users")
            self.send_json(401, {"error": "Unauthorized"})

server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
with open("/tmp/policy_dynamic_expected.json", "w") as f:
    json.dump(expected, f)
server.serve_forever()
PY

    python3 /tmp/policy_mock_server.py &
    MOCK_PID=$!

    for _ in $(seq 1 50); do
        test -f /tmp/policy_dynamic_expected.json && break
        kill -0 "$MOCK_PID" 2>/dev/null || return 1
        sleep 0.1
    done
    test -f /tmp/policy_dynamic_expected.json || return 1

    # Removing the old report ensures this execution, rather than a static file,
    # must produce the dynamically correct result.
    rm -f /home/user/compliance_report.json
    timeout 20s python3 /home/user/policy_tester.py || return 1

    cat <<'TEST_EOF' > /tmp/test_dynamic_report.py
import json
import os

def test_tester_exercised_api_and_generated_dynamic_report():
    report_path = "/home/user/compliance_report.json"
    assert os.path.isfile(report_path), "policy_tester.py did not generate the report"

    with open("/tmp/policy_dynamic_expected.json") as f:
        expected = json.load(f)
    with open(report_path) as f:
        actual = json.load(f)

    assert set(actual) == {"cookie_security", "missing_security_headers", "redacted_users"}
    assert actual == expected, f"Dynamic report mismatch: {actual!r}"
    assert actual["missing_security_headers"] == sorted(actual["missing_security_headers"])

    with open("/tmp/policy_dynamic_events.jsonl") as f:
        events = [json.loads(line)["event"] for line in f if line.strip()]
    assert "valid_login" in events, "Tester did not perform the required login request"
    assert "authorized_users" in events, "Tester did not query /api/users with the issued session cookie"
TEST_EOF
    python3 -m pytest /tmp/test_dynamic_report.py -x --tb=short || return 1
    return 0
}

if run_checks; then
    RESULT=1
else
    RESULT=0
fi

if test -n "$MOCK_PID"; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
fi

echo "$RESULT" > /logs/verifier/reward.txt
