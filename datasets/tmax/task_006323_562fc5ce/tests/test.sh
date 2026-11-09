#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import re
import pytest

def xor_decrypt(hex_cipher: str, key: str = "S3cr3tK3y") -> str:
    cipher_bytes = bytes.fromhex(hex_cipher)
    key_bytes = key.encode()
    plain = bytearray()
    for i in range(len(cipher_bytes)):
        plain.append(cipher_bytes[i] ^ key_bytes[i % len(key_bytes)])
    return plain.decode()

def redact_ssn(text: str) -> str:
    # SSN format: XXX-XX-XXXX where X is a digit
    return re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '[REDACTED]', text)

def compute_expected_report(log_filepath: str) -> list:
    expected_report = []
    with open(log_filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            payload = json.loads(base64.b64decode(line).decode())
            filename = payload.get("filename", "")
            enc_content = payload.get("content", "")

            is_traversal = "../" in filename
            decrypted_content = xor_decrypt(enc_content)
            redacted_content = redact_ssn(decrypted_content)

            expected_report.append({
                "filename": filename,
                "is_traversal": is_traversal,
                "redacted_content": redacted_content
            })

    return expected_report

def test_ir_report_exists_and_valid():
    """Verify that the ir_report.json is generated correctly based on the incident logs."""
    log_filepath = "/home/user/incident_logs.txt"
    report_filepath = "/home/user/ir_report.json"

    assert os.path.exists(log_filepath), f"Prerequisite file missing: {log_filepath}"
    assert os.path.exists(report_filepath), f"The required report file was not created: {report_filepath}"
    assert os.path.isfile(report_filepath), f"Expected a file, but found a directory: {report_filepath}"

    expected_data = compute_expected_report(log_filepath)

    try:
        with open(report_filepath, "r") as f:
            actual_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {report_filepath} as valid JSON: {e}")

    assert isinstance(actual_data, list), f"Expected the JSON report to be a list (array), but got {type(actual_data).__name__}"
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} entries in the report, found {len(actual_data)}"

    for i, (expected, actual) in enumerate(zip(expected_data, actual_data)):
        assert isinstance(actual, dict), f"Entry at index {i} is not a JSON object"

        # Check filename
        assert "filename" in actual, f"Entry {i} is missing the 'filename' key"
        assert actual["filename"] == expected["filename"], f"Entry {i} filename mismatch. Expected {expected['filename']}, got {actual['filename']}"

        # Check is_traversal
        assert "is_traversal" in actual, f"Entry {i} is missing the 'is_traversal' key"
        assert actual["is_traversal"] == expected["is_traversal"], f"Entry {i} is_traversal mismatch. Expected {expected['is_traversal']}, got {actual['is_traversal']}"

        # Check redacted_content
        assert "redacted_content" in actual, f"Entry {i} is missing the 'redacted_content' key"
        assert actual["redacted_content"] == expected["redacted_content"], f"Entry {i} redacted_content mismatch. Expected {expected['redacted_content']}, got {actual['redacted_content']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
