#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_source_and_executable_exist():
    assert os.path.isfile("/home/user/process.cpp"), "/home/user/process.cpp does not exist."
    assert os.path.isfile("/home/user/process"), "/home/user/process executable does not exist."
    assert os.access("/home/user/process", os.X_OK), "/home/user/process is not executable."

def test_clean_audit_csv_exists():
    assert os.path.isfile("/home/user/clean_audit.csv"), "/home/user/clean_audit.csv does not exist."

def test_clean_audit_csv_content():
    expected_content = """Timestamp,Author,ConfigValue
2023-10-01T12:00:00Z,Alice,"Changed database IP from [REDACTED] to [REDACTED]"
2023-10-01T12:05:00Z,Bob,"Updated firewall rules:
- Block [REDACTED]
- Allow [REDACTED]
Ensure these are applied."
2023-10-01T12:10:00Z,Charlie,"Simple config change"
2023-10-01T12:15:00Z,Dave,"Added a literal quote "" inside the config for server [REDACTED]"
"""
    with open("/home/user/clean_audit.csv", "r", encoding="utf-8") as f:
        actual_content = f.read()

    # Normalize line endings to avoid failure due to CRLF vs LF
    actual_content = actual_content.replace("\r\n", "\n")
    expected_content = expected_content.replace("\r\n", "\n")

    assert actual_content.strip() == expected_content.strip(), (
        "The content of /home/user/clean_audit.csv does not match the expected output. "
        "Make sure embedded newlines, escaped quotes, and IPv4 anonymization are handled correctly."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
