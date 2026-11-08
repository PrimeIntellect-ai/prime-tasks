#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier

verify() {
    if [ ! -f /home/user/auditor.go ] || [ -L /home/user/auditor.go ]; then
        echo "Missing or invalid /home/user/auditor.go"
        return 1
    fi

    go build -o /tmp/auditor_verified /home/user/auditor.go || return 1

    cat > /home/user/server_response.json <<'EOF'
{
  "logs": [
    "User admin logged in with CC 1234-5678-9012-3456 at 10:00 AM",
    "Payment processed for CC 9876-5432-1098-7654 successfully",
    "Invalid login attempt by guest"
  ]
}
EOF

    rm -f /home/user/redacted.json /home/user/auditor_token.txt /home/user/csp.conf
    (cd /home/user && /tmp/auditor_verified) || return 1

    cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import json
import hmac
import hashlib
import base64
import pytest

def test_redacted_json():
    file_path = "/home/user/redacted.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} does not contain valid JSON.")

    expected_logs = [
        "User admin logged in with CC ****-****-****-3456 at 10:00 AM",
        "Payment processed for CC ****-****-****-7654 successfully",
        "Invalid login attempt by guest"
    ]

    assert "logs" in data, f"'logs' key missing in {file_path}."
    assert data["logs"] == expected_logs, f"Content of 'logs' in {file_path} does not match the expected redacted output."

def test_auditor_token():
    file_path = "/home/user/auditor_token.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    def encode_b64url(data):
        return base64.urlsafe_b64encode(data).rstrip(b'=')

    header = b'{"alg":"HS256","typ":"JWT"}'
    payload = b'{"role":"auditor"}'
    secret = b'auditor-secret-2023'

    header_b64 = encode_b64url(header)
    payload_b64 = encode_b64url(payload)
    msg = header_b64 + b"." + payload_b64

    sig = hmac.new(secret, msg, hashlib.sha256).digest()
    sig_b64 = encode_b64url(sig)
    expected_jwt = (msg + b"." + sig_b64).decode('utf-8')

    with open(file_path, 'r') as f:
        actual_jwt = f.read().strip()

    assert actual_jwt == expected_jwt, f"JWT in {file_path} does not match the expected token."

def test_csp_conf():
    file_path = "/home/user/csp.conf"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    expected_csp = 'add_header Content-Security-Policy "default-src \'self\'";'

    with open(file_path, 'r') as f:
        actual_csp = f.read().strip()

    assert actual_csp == expected_csp, f"Content of {file_path} does not match the expected CSP directive."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    python3 <<'DYNAMIC_EOF'
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import subprocess


def card():
    return "-".join(f"{secrets.randbelow(10000):04d}" for _ in range(4))

cards = [card(), card(), card()]
source = {
    "logs": [
        f"Random account used {cards[0]} during review",
        f"Two payments: {cards[1]} and {cards[2]}",
        "No card appears in this message",
        "Do not alter near-match 1234-5678-9012-345"
    ],
    "metadata": {"preserve": True, "count": 4}
}

with open('/home/user/server_response.json', 'w') as f:
    json.dump(source, f)

for path in ('/home/user/redacted.json', '/home/user/auditor_token.txt', '/home/user/csp.conf'):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

subprocess.run(['/tmp/auditor_verified'], cwd='/home/user', check=True)

with open('/home/user/redacted.json') as f:
    actual = json.load(f)

pattern = re.compile(r'\d{4}-\d{4}-\d{4}-\d{4}')
expected = json.loads(json.dumps(source))
expected['logs'] = [pattern.sub(lambda m: '****-****-****-' + m.group(0)[-4:], text)
                    for text in source['logs']]
assert actual == expected, 'Program did not correctly redact verifier-generated input while preserving JSON structure.'

encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
header = b'{"alg":"HS256","typ":"JWT"}'
payload = b'{"role":"auditor"}'
message = encode(header) + b'.' + encode(payload)
signature = encode(hmac.new(b'auditor-secret-2023', message, hashlib.sha256).digest())
expected_token = (message + b'.' + signature).decode()
with open('/home/user/auditor_token.txt') as f:
    assert f.read().strip() == expected_token, 'JWT is incorrect after execution on generated input.'

with open('/home/user/csp.conf') as f:
    assert f.read().strip() == 'add_header Content-Security-Policy "default-src \'self\'";', 'CSP directive is incorrect after execution on generated input.'
DYNAMIC_EOF
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
