#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop whatever process currently owns port 8080 so verification can use a
# controlled service and observe the submitted script's requests.
python3 - <<'PY'
import os
import signal

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if state == '0A' and int(local.rsplit(':', 1)[1], 16) == 8080:
                    inodes.add(fields[9])
    except OSError:
        pass

for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.server
import json
import os
import secrets
import subprocess
import threading

SCRIPT_PATH = "/home/user/generate_audit.sh"
REPORT_PATH = "/home/user/audit_report.json"
SQLI = "' OR 1=1 --"
XSS = "<script>alert('audit')</script>"


def decode_segment(segment):
    segment += "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(segment.encode()).decode())


def valid_none_admin_token(auth):
    if not auth.startswith("Bearer "):
        return False
    parts = auth[7:].split(".")
    if len(parts) not in (2, 3) or (len(parts) == 3 and parts[2] != ""):
        return False
    try:
        header = decode_segment(parts[0])
        payload = decode_segment(parts[1])
    except Exception:
        return False
    return str(header.get("alg", "")).lower() == "none" and payload.get("role") == "admin"


class ReusableServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True


def execute_against(secret, sqli_code, xss_body):
    requests_seen = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def send_raw(self, status, body, content_type):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            auth = self.headers.get("Authorization", "")
            requests_seen.append(("GET", self.path, auth, None))
            if self.path == "/admin" and valid_none_admin_token(auth):
                body = json.dumps({"status": "success", "secret_data": secret})
                self.send_raw(200, body, "application/json")
            else:
                self.send_raw(401, json.dumps({"error": "Invalid token"}), "application/json")

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            try:
                data = json.loads(raw.decode())
                query = data.get("query")
            except Exception:
                query = None
            requests_seen.append(("POST", self.path, self.headers.get("Authorization", ""), query))
            if self.path != "/search":
                self.send_raw(404, "not found", "text/plain")
            elif query == SQLI:
                self.send_raw(sqli_code, json.dumps({"error": "Database syntax error near '--'"}), "application/json")
            elif query == XSS:
                self.send_raw(200, xss_body, "text/html")
            else:
                self.send_raw(200, f"<html><body>Results for {query}</body></html>", "text/html")

        def log_message(self, *args):
            pass

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    server = ReusableServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode == 0, f"Scanner exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(REPORT_PATH), f"The audit report {REPORT_PATH} does not exist."
    with open(REPORT_PATH) as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {REPORT_PATH} does not contain valid JSON."

    admin_requests = [r for r in requests_seen if r[0] == "GET" and r[1] == "/admin"]
    assert any(valid_none_admin_token(r[2]) for r in admin_requests), \
        "The script did not send /admin a forged alg:none JWT claiming the admin role."
    assert any(r[0] == "POST" and r[1] == "/search" and r[3] == SQLI for r in requests_seen), \
        "The script did not send the exact SQL injection query to /search."
    assert any(r[0] == "POST" and r[1] == "/search" and r[3] == XSS for r in requests_seen), \
        "The script did not send the exact XSS query to /search."
    assert set(report) == {"jwt_bypass_successful", "admin_secret", "sqli_response_code", "xss_response_body"}, \
        "The report does not have exactly the required structure."
    return report


def test_generate_audit_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_audit_report_json_content():
    expected_xss_body = "<html><body>Results for <script>alert('audit')</script></body></html>"
    report_data = execute_against("FLAG{jwt_bypass_successful_9921}", 500, expected_xss_body)

    assert report_data.get("jwt_bypass_successful") is True, "The 'jwt_bypass_successful' field is missing or not True."
    assert report_data.get("admin_secret") == "FLAG{jwt_bypass_successful_9921}", "The 'admin_secret' field does not match the expected secret data."
    assert report_data.get("sqli_response_code") == 500, "The 'sqli_response_code' field does not match the expected HTTP status code (500)."
    assert report_data.get("xss_response_body") == expected_xss_body, "The 'xss_response_body' field does not match the expected raw response body."


def test_report_is_derived_from_live_responses():
    nonce = secrets.token_hex(16)
    secret = f"FLAG{{dynamic_{nonce}}}"
    xss_body = f"<html data-audit='{nonce}'><body>Results for {XSS}</body></html>"
    report_data = execute_against(secret, 418, xss_body)

    assert report_data["jwt_bypass_successful"] is True
    assert report_data["admin_secret"] == secret
    assert report_data["sqli_response_code"] == 418
    assert report_data["xss_response_body"] == xss_body
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
