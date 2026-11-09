#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hmac
import hashlib

def _decode_base64_url_safe(s):
    # Add padding if necessary
    pad = len(s) % 4
    if pad:
        s += "=" * (4 - pad)
    return base64.urlsafe_b64decode(s)

def _compute_expected_audit_trail():
    secret_path = "/home/user/secret.key"
    logs_path = "/home/user/upload_logs.txt"

    assert os.path.isfile(secret_path), f"Missing {secret_path}"
    assert os.path.isfile(logs_path), f"Missing {logs_path}"

    with open(secret_path, "r") as f:
        secret_key = f.read().strip().encode('utf-8')

    with open(logs_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_trail = []

    for line in lines:
        parts = line.split(" | ")
        if len(parts) != 2:
            continue
        token, encoded_filename = parts

        try:
            filename = base64.b64decode(encoded_filename).decode('utf-8')
        except Exception:
            continue

        filename_lower = filename.lower()
        if "../" in filename_lower or "..%2f" in filename_lower:
            token_parts = token.split(".")
            if len(token_parts) != 2:
                continue

            payload_str, mac_str = token_parts

            try:
                payload_json = json.loads(_decode_base64_url_safe(payload_str).decode('utf-8'))
                user = payload_json.get("user", "")
            except Exception:
                user = ""

            expected_mac = base64.urlsafe_b64encode(
                hmac.new(secret_key, payload_str.encode('utf-8'), hashlib.sha256).digest()
            ).decode('utf-8').rstrip("=")

            signature_valid = hmac.compare_digest(mac_str, expected_mac)

            expected_trail.append({
                "user": user,
                "malicious_payload": filename,
                "signature_valid": signature_valid
            })

    return expected_trail

def test_audit_trail_exists_and_correct():
    audit_file = "/home/user/audit_trail.json"
    assert os.path.isfile(audit_file), f"Audit trail file {audit_file} does not exist."

    with open(audit_file, "r") as f:
        try:
            actual_trail = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {audit_file} is not valid JSON."

    expected_trail = _compute_expected_audit_trail()

    assert isinstance(actual_trail, list), f"Expected audit trail to be a JSON array, got {type(actual_trail).__name__}."
    assert len(actual_trail) == len(expected_trail), f"Expected {len(expected_trail)} entries in audit trail, got {len(actual_trail)}."

    for i, (expected, actual) in enumerate(zip(expected_trail, actual_trail)):
        assert isinstance(actual, dict), f"Entry {i} is not a JSON object."
        assert "user" in actual, f"Entry {i} missing 'user' key."
        assert "malicious_payload" in actual, f"Entry {i} missing 'malicious_payload' key."
        assert "signature_valid" in actual, f"Entry {i} missing 'signature_valid' key."

        assert actual["user"] == expected["user"], f"Entry {i}: expected user '{expected['user']}', got '{actual['user']}'."
        assert actual["malicious_payload"] == expected["malicious_payload"], f"Entry {i}: expected payload '{expected['malicious_payload']}', got '{actual['malicious_payload']}'."
        assert actual["signature_valid"] == expected["signature_valid"], f"Entry {i}: expected signature_valid {expected['signature_valid']}, got {actual['signature_valid']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
