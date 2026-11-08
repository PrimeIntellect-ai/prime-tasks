#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cracked_txt():
    file_path = "/home/user/cracked.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "password", f"Content of {file_path} is incorrect. Expected 'password', got '{content}'."

def test_payload_txt():
    file_path = "/home/user/payload.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_payload = "cat /etc/shadow > /tmp/out"
    assert content == expected_payload, f"Content of {file_path} is incorrect. Expected '{expected_payload}', got '{content}'."

def test_redacted_dump_txt():
    file_path = "/home/user/redacted_dump.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_content = """PID USER COMMAND
101 root /sbin/init
102 root /lib/systemd/systemd-journald
103 admin /usr/bin/python3 /opt/admin/auth.py --user root --hash [REDACTED]
104 www-data bash -c "echo '[REDACTED]' | base64 -d | sh"
105 user top"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {file_path} does not match the expected redacted output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
