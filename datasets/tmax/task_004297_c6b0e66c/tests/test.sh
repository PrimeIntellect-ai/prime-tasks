#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1

# The requested artifact must exist and must use PyJWT to generate the token.
python3 - <<'PY' || ok=0
import ast
import os

path = "/home/user/enforcer.py"
assert os.path.isfile(path), f"Missing required script: {path}"
assert not os.path.islink(path), f"{path} must be a regular file, not a symlink"
with open(path, "r", encoding="utf-8") as f:
    source = f.read()
assert source.strip(), f"{path} is empty"
tree = ast.parse(source, filename=path)

jwt_modules = set()
encode_names = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name == "jwt" or alias.name.startswith("jwt."):
                jwt_modules.add(alias.asname or alias.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom):
        if node.module and (node.module == "jwt" or node.module.startswith("jwt.")):
            for alias in node.names:
                if alias.name == "encode":
                    encode_names.add(alias.asname or alias.name)

uses_encode = False
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    if isinstance(node.func, ast.Name) and node.func.id in encode_names:
        uses_encode = True
    elif (isinstance(node.func, ast.Attribute) and node.func.attr == "encode"
          and isinstance(node.func.value, ast.Name)
          and node.func.value.id in jwt_modules):
        uses_encode = True

assert jwt_modules or encode_names, "enforcer.py must import the PyJWT 'jwt' package"
assert uses_encode, "enforcer.py must call PyJWT's encode function to generate the JWT"
PY

# Ensure the supplied endpoint is running, then execute the submitted scanner.
if [ "$ok" -eq 1 ]; then
    if ! pgrep -f '[p]ython3 /tmp/server.py' >/dev/null; then
        nohup python3 /tmp/server.py >/tmp/verifier-original-server.log 2>&1 &
    fi
    ready=0
    for _ in $(seq 1 30); do
        python3 - <<'PY' >/dev/null 2>&1 && ready=1 && break
import socket
s = socket.create_connection(("127.0.0.1", 8443), timeout=0.2)
s.close()
PY
        sleep 0.1
    done
    [ "$ready" -eq 1 ] || ok=0
fi

if [ "$ok" -eq 1 ]; then
    timeout 30s python3 /home/user/enforcer.py || ok=0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hmac
import hashlib
import pytest

REPORT_PATH = "/home/user/report.json"

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}. Did the script execute and create the file?"

def test_report_json_structure_and_values():
    assert os.path.isfile(REPORT_PATH), "Report file missing."
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    assert "issuer_cn" in data, "Missing 'issuer_cn' key in the report JSON."
    assert data["issuer_cn"] == "DevSecOpsLocal", f"Expected 'issuer_cn' to be 'DevSecOpsLocal', got {data['issuer_cn']}"

    assert "status_code" in data, "Missing 'status_code' key in the report JSON."
    assert data["status_code"] == 200, f"Expected 'status_code' to be 200, got {data['status_code']}"

    assert "policy_violations" in data, "Missing 'policy_violations' key in the report JSON."
    violations = data["policy_violations"]
    assert isinstance(violations, list), "'policy_violations' must be a JSON array (list)."
    expected_violations = {"Strict-Transport-Security", "Content-Security-Policy"}
    assert set(violations) == expected_violations, f"Expected policy violations {expected_violations}, got {set(violations)}"
    assert len(violations) == 2, "Expected exactly 2 policy violations."

def test_jwt_validity_and_payload():
    assert os.path.isfile(REPORT_PATH), "Report file missing."
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Cannot parse JSON to check JWT.")

    assert "jwt_generated" in data, "Missing 'jwt_generated' key in the report JSON."
    token = data["jwt_generated"]

    parts = token.split('.')
    assert len(parts) == 3, "The 'jwt_generated' value is not a valid JWT string (does not have 3 dot-separated parts)."

    header_b64, payload_b64, sig_b64 = parts
    secret = "devsecops_secret_2024"
    msg = f"{header_b64}.{payload_b64}".encode('utf-8')
    expected_sig = hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()
    expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('utf-8').rstrip('=')

    assert sig_b64 == expected_sig_b64, "JWT signature verification failed. Ensure it is signed with the correct secret ('devsecops_secret_2024') and algorithm (HS256)."

    payload_padded = payload_b64 + '=' * (-len(payload_b64) % 4)
    try:
        payload_bytes = base64.urlsafe_b64decode(payload_padded)
        payload = json.loads(payload_bytes)
    except Exception as e:
        pytest.fail(f"Failed to decode JWT payload: {e}")

    expected_payload = {"sub": "policy_scanner", "role": "auditor"}
    for k, v in expected_payload.items():
        assert payload.get(k) == v, f"JWT payload missing or incorrect for key '{k}'. Expected '{v}', got '{payload.get(k)}'"
TEST_EOF

if [ "$ok" -eq 1 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || ok=0
fi

# Replace the fixed service with verifier-generated TLS services and rerun the
# artifact. This proves that the report is derived from live TLS and HTTP data.
if [ "$ok" -eq 1 ]; then
    pkill -f '[p]ython3 /tmp/server.py' >/dev/null 2>&1 || true
    sleep 0.5
    python3 - <<'PY' || ok=0
import http.server
import json
import os
import secrets
import ssl
import subprocess
import tempfile
import threading
import time
import jwt

SCRIPT = "/home/user/enforcer.py"
REPORT = "/home/user/report.json"
REQUIRED = [
    "X-Content-Type-Options",
    "Strict-Transport-Security",
    "Content-Security-Policy",
]

# Select two distinct header combinations at verification time, neither of
# which is the fixed combination used by the image's original server.
masks = secrets.SystemRandom().sample([0, 2, 3, 4, 5, 6, 7], 2)

class ReusableHTTPServer(http.server.HTTPServer):
    allow_reuse_address = True


def run_case(mask):
    cn = "Verifier-" + secrets.token_hex(8)
    included = {name for i, name in enumerate(REQUIRED) if mask & (1 << i)}
    seen = []

    with tempfile.TemporaryDirectory() as td:
        cert = os.path.join(td, "cert.pem")
        key = os.path.join(td, "key.pem")
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-keyout", key, "-out", cert,
            "-subj", f"/CN={cn}/O=Verifier",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                auth = self.headers.get("Authorization")
                seen.append((self.path, auth))
                valid = False
                if auth and auth.startswith("Bearer "):
                    try:
                        payload = jwt.decode(
                            auth[7:], "devsecops_secret_2024", algorithms=["HS256"]
                        )
                        valid = (payload.get("sub") == "policy_scanner" and
                                 payload.get("role") == "auditor")
                    except Exception:
                        valid = False
                if self.path != "/api/health":
                    self.send_response(404)
                    self.end_headers()
                    return
                if not valid:
                    self.send_response(401)
                    self.end_headers()
                    return
                self.send_response(200)
                for name in included:
                    self.send_header(name, "verifier-present")
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status":"dynamic"}')

            def log_message(self, fmt, *args):
                pass

        server = ReusableHTTPServer(("127.0.0.1", 8443), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=cert, keyfile=key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            if os.path.exists(REPORT):
                os.unlink(REPORT)
            completed = subprocess.run(
                ["python3", SCRIPT], timeout=30, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True
            )
            assert completed.returncode == 0, (
                f"enforcer.py failed against dynamic endpoint: {completed.stderr}"
            )
            assert os.path.isfile(REPORT), "enforcer.py did not create report.json"
            with open(REPORT, "r", encoding="utf-8") as f:
                data = json.load(f)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    assert seen, "No HTTPS GET request reached the assessment endpoint"
    path, auth = seen[-1]
    assert path == "/api/health", f"Expected GET /api/health, received {path!r}"
    assert auth and auth.startswith("Bearer "), "Request lacked a Bearer JWT"
    request_token = auth[7:]
    assert data.get("jwt_generated") == request_token, (
        "Reported JWT was not the JWT sent in the Authorization header"
    )
    decoded = jwt.decode(request_token, "devsecops_secret_2024", algorithms=["HS256"])
    assert decoded.get("sub") == "policy_scanner"
    assert decoded.get("role") == "auditor"
    assert data.get("issuer_cn") == cn, (
        f"Expected dynamically generated issuer CN {cn!r}, got {data.get('issuer_cn')!r}"
    )
    assert data.get("status_code") == 200
    violations = data.get("policy_violations")
    assert isinstance(violations, list)
    expected_missing = set(REQUIRED) - included
    assert set(violations) == expected_missing, (
        f"Expected missing headers {expected_missing}, got {violations}"
    )
    assert len(violations) == len(expected_missing)

for selected_mask in masks:
    run_case(selected_mask)
PY
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
