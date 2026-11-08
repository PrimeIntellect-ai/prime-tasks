#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_vulnerable_perms_file():
    target_file = "/home/user/vulnerable_perms.txt"
    assert os.path.isfile(target_file), f"File {target_file} does not exist. Did you complete the Permission Auditing task?"

    with open(target_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_path = "/home/user/audit_target/tmp_cache.txt"
    assert expected_path in lines, f"Expected {expected_path} to be in {target_file}."

    expected_paths = {
        "/home/user/audit_target/tmp_cache.txt",
        "/home/user/audit_target/secret_data.enc",
        "/home/user/audit_target/server.log",
    }
    assert len(lines) == 3, f"Expected exactly 3 vulnerable file paths in {target_file}, found {len(lines)}."
    assert set(lines) == expected_paths, f"Content of {target_file} is incorrect. Expected {sorted(expected_paths)}, but got {lines}."

def test_cwe_report_file():
    target_file = "/home/user/cwe_report.txt"
    assert os.path.isfile(target_file), f"File {target_file} does not exist. Did you complete the CWE Identification task?"

    with open(target_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_cwes = ["CWE-327", "CWE-798"]
    assert lines == expected_cwes, f"Content of {target_file} is incorrect. Expected {expected_cwes}, but got {lines}."

def test_decrypted_data_file():
    target_file = "/home/user/decrypted_data.txt"
    assert os.path.isfile(target_file), f"File {target_file} does not exist. Did you complete the Algorithmic Cryptanalysis task?"

    with open(target_file, "r") as f:
        content = f.read().strip()

    expected_content = "CONFIDENTIAL: The backup server password is 'hunter2'."
    assert content == expected_content, f"Content of {target_file} does not match expected decrypted text."

def test_redacted_server_log_file():
    target_file = "/home/user/redacted_server.log"
    assert os.path.isfile(target_file), f"File {target_file} does not exist. Did you complete the Data Redaction task?"

    with open(target_file, "r") as f:
        content = f.read()

    # Check that sensitive data is redacted
    assert "1234567890123456" not in content, "Found unredacted credit card number in the log file."
    assert "aB3dE6gH9jK2mN5p" not in content, "Found unredacted API key in the log file."
    assert "XYZ123ABC9876543" not in content, "Found unredacted API key in the log file."

    # Check that redaction strings are present
    assert "XXXX-XXXX-XXXX-XXXX" in content, "Expected credit card redaction string 'XXXX-XXXX-XXXX-XXXX' not found."
    assert "API_KEY=REDACTED" in content, "Expected API key redaction string 'API_KEY=REDACTED' not found."

    # Check exact expected content based on original log structure
    expected_lines = [
        "[INFO] User admin logged in successfully.",
        "[DEBUG] Checking API_KEY=REDACTED for permissions.",
        "[ERROR] Failed to process payment for card XXXX-XXXX-XXXX-XXXX due to timeout.",
        "[INFO] Another API_KEY=REDACTED was used.",
        "[DEBUG] User profile updated."
    ]

    lines = [line.strip() for line in content.strip().split('\n')]
    assert lines == expected_lines, f"Redacted log content does not match exactly. Expected: {expected_lines}, Got: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
