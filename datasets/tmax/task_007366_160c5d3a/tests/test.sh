#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hmac
import hashlib
import base64
import re

RAW_LOG = "/home/user/raw_access.log"
SECRET_KEY = "/home/user/.secret_key"
BLOCKED_IPS = "/home/user/blocked_ips.txt"
AUDIT_TRAIL = "/home/user/audit_trail.json"
AUDIT_TRAIL_SHA256 = "/home/user/audit_trail.sha256"

def get_expected_data():
    with open(SECRET_KEY, "rb") as f:
        secret_key = f.read()

    expected_blocked_ips = set()
    expected_audit_trail = []

    with open(RAW_LOG, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 4:
                continue

            ip, ts, token, b64_payload = parts
            msg = f"{ip}|{ts}|{b64_payload}".encode()
            expected_token = hmac.new(secret_key, msg, hashlib.sha256).hexdigest()

            if hmac.compare_digest(token, expected_token):
                # Valid
                decoded_payload = base64.b64decode(b64_payload).decode()
                payload_data = json.loads(decoded_payload)

                # Redact CC
                cc = payload_data.get("cc", "")
                if cc:
                    # Replace first 12 digits with X
                    redacted_cc = re.sub(r'\d', 'X', cc[:14]) + cc[14:]
                    payload_data["cc"] = redacted_cc

                expected_audit_trail.append({
                    "ip": ip,
                    "timestamp": ts,
                    "payload_data": payload_data
                })
            else:
                # Invalid
                expected_blocked_ips.add(ip)

    return sorted(list(expected_blocked_ips)), expected_audit_trail

def test_blocked_ips():
    assert os.path.exists(BLOCKED_IPS), f"Missing file: {BLOCKED_IPS}"

    expected_ips, _ = get_expected_data()

    with open(BLOCKED_IPS, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, f"Blocked IPs do not match expected. Expected {expected_ips}, got {actual_ips}"

def test_audit_trail_json():
    assert os.path.exists(AUDIT_TRAIL), f"Missing file: {AUDIT_TRAIL}"

    _, expected_audit_trail = get_expected_data()

    with open(AUDIT_TRAIL, "r") as f:
        try:
            actual_audit_trail = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{AUDIT_TRAIL} is not valid JSON."

    assert isinstance(actual_audit_trail, list), f"{AUDIT_TRAIL} must contain a JSON array."
    assert len(actual_audit_trail) == len(expected_audit_trail), f"Expected {len(expected_audit_trail)} valid entries, found {len(actual_audit_trail)}."

    for i, (actual, expected) in enumerate(zip(actual_audit_trail, expected_audit_trail)):
        assert "ip" in actual, f"Entry {i} missing 'ip'"
        assert "timestamp" in actual, f"Entry {i} missing 'timestamp'"
        assert "redacted_payload" in actual, f"Entry {i} missing 'redacted_payload'"

        assert actual["ip"] == expected["ip"], f"Entry {i} IP mismatch"
        assert actual["timestamp"] == expected["timestamp"], f"Entry {i} timestamp mismatch"

        try:
            decoded_actual = base64.b64decode(actual["redacted_payload"]).decode()
            actual_payload_data = json.loads(decoded_actual)
        except Exception as e:
            assert False, f"Entry {i} 'redacted_payload' is not valid base64-encoded JSON: {e}"

        assert actual_payload_data == expected["payload_data"], f"Entry {i} payload mismatch. Expected {expected['payload_data']}, got {actual_payload_data}"

def test_audit_trail_sha256():
    assert os.path.exists(AUDIT_TRAIL_SHA256), f"Missing file: {AUDIT_TRAIL_SHA256}"
    assert os.path.exists(AUDIT_TRAIL), f"Missing file: {AUDIT_TRAIL}"

    with open(AUDIT_TRAIL, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    with open(AUDIT_TRAIL_SHA256, "r") as f:
        checksum_content = f.read().strip()

    # standard sha256sum format: "<hash>  <filename>"
    # we just check if the hash is present in the file
    assert actual_hash in checksum_content, f"SHA256 checksum in {AUDIT_TRAIL_SHA256} does not match the actual hash of {AUDIT_TRAIL}. Expected hash: {actual_hash}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
