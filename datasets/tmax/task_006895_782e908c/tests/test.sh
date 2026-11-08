#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_ssh_vuln_report():
    report_path = "/home/user/ssh_vuln_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist. Did you create it?"

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "PermitRootLogin yes",
        "PasswordAuthentication yes"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected '{expected}' to be in {report_path}, but it was missing."

    # Ensure no other vulnerable settings were incorrectly extracted (like PermitEmptyPasswords no)
    for line in lines:
        assert line in expected_lines, f"Unexpected line '{line}' found in {report_path}."

def test_redacted_logs():
    redacted_path = "/home/user/redacted_logs.txt"
    assert os.path.isfile(redacted_path), f"File {redacted_path} does not exist. Did you create it?"

    with open(redacted_path, 'r') as f:
        content = f.read()

    # The original file has the private key block. It should be replaced with [REDACTED_KEY].
    assert "-----BEGIN" not in content, f"Found '-----BEGIN' in {redacted_path}. The private key was not fully redacted."
    assert "-----END" not in content, f"Found '-----END' in {redacted_path}. The private key was not fully redacted."
    assert "[REDACTED_KEY]" in content, f"Expected '[REDACTED_KEY]' in {redacted_path}."

    # Check the exact expected content
    expected_content = """[2023-10-24 10:00:01] [INFO] sshd service started
[2023-10-24 10:02:15] [WARN] Invalid configuration detected
[2023-10-24 10:05:22] [ERROR] Debug dump of application crash:
[REDACTED_KEY]
[2023-10-24 10:05:23] [INFO] Connection closed from 192.168.1.50
[2023-10-24 10:10:00] [INFO] System shutdown initiated"""

    # Normalize newlines for comparison
    content_normalized = "\n".join([line.strip() for line in content.strip().splitlines()])
    expected_normalized = "\n".join([line.strip() for line in expected_content.strip().splitlines()])

    assert content_normalized == expected_normalized, f"The content of {redacted_path} does not match the expected redacted logs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
