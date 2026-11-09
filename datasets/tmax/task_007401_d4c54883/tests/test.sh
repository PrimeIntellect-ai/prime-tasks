#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import base64
import subprocess


def decode_base64url(s):
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s + '=' * (-len(s) % 4))


def assert_canonical_unpadded_base64url(segment, name):
    assert '=' not in segment, f"JWT {name} must use unpadded Base64Url encoding."
    assert re.fullmatch(r'[A-Za-z0-9_-]+', segment), \
        f"JWT {name} contains characters outside the Base64Url alphabet."
    decoded = decode_base64url(segment)
    canonical = base64.urlsafe_b64encode(decoded).decode('ascii').rstrip('=')
    assert segment == canonical, f"JWT {name} is not canonically Base64Url encoded."
    return decoded


def original_admin_payload():
    log_path = "/home/user/auth_logs.txt"
    assert os.path.isfile(log_path), f"Missing file: {log_path}"
    with open(log_path, "r") as f:
        logs = f.read()

    match = re.search(r'user:\s*admin\s*-\s*token:\s*(\S+)', logs)
    assert match, "Could not find the legitimate admin JWT in auth_logs.txt."
    original_parts = match.group(1).split('.')
    assert len(original_parts) == 3, "Admin JWT in auth_logs.txt is malformed."
    payload = json.loads(decode_base64url(original_parts[1]))
    assert payload == {"user": "admin", "role": "superuser"}, \
        "The admin payload in auth_logs.txt was unexpectedly modified."
    return payload


def read_forged_token():
    path = "/home/user/audit_forged_jwt.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        return f.read().strip()


def test_audit_forged_jwt():
    path = "/home/user/audit_forged_jwt.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, f"Forged JWT in {path} does not have exactly 3 parts (header.payload.signature)."

    header_b64, payload_b64, signature = parts

    assert_canonical_unpadded_base64url(header_b64, "header")
    assert_canonical_unpadded_base64url(payload_b64, "payload")

    try:
        header = json.loads(decode_base64url(header_b64))
    except Exception as e:
        assert False, f"Failed to decode JWT header: {e}"

    try:
        payload = json.loads(decode_base64url(payload_b64))
    except Exception as e:
        assert False, f"Failed to decode JWT payload: {e}"

    assert header.get("alg", "").lower() == "none", f"JWT header 'alg' must be 'none', got: {header.get('alg')}"
    assert payload.get("user") == "admin", f"JWT payload 'user' must be 'admin', got: {payload.get('user')}"
    assert payload.get("role") == "superuser", f"JWT payload 'role' must be 'superuser', got: {payload.get('role')}"
    assert signature == "", f"JWT signature must be empty for 'none' algorithm, got: {signature}"
    assert payload == original_admin_payload(), \
        "Forged JWT payload must match the original admin JWT claims exactly."


def test_audit_report():
    path = "/home/user/audit_report.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_output = "CRITICAL: Access granted to superuser. Compliance violation detected!"
    assert content == expected_output, f"Output in {path} does not match expected output.\nExpected: {expected_output}\nGot: {content}"

    token = read_forged_token()
    result = subprocess.run(
        ["/home/user/auth_tool.py", token],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, \
        f"auth_tool.py rejected the forged token (exit {result.returncode}): {result.stderr.decode(errors='replace')}"

    expected_stdout = (expected_output + "\n").encode()
    assert result.stdout == expected_stdout, \
        f"Unexpected stdout from auth_tool.py: {result.stdout!r}"

    with open(path, "rb") as f:
        report_bytes = f.read()
    assert report_bytes == result.stdout, \
        "audit_report.txt must contain the exact standard output produced by auth_tool.py."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
