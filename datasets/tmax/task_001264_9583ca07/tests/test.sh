#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_vuln_audit_content():
    file_path = "/home/user/vuln_audit.tsv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_content = "3\tCWE-614\n5\tCWE-327\n8\tCWE-614\n9\tCWE-327\n"

    with open(file_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), f"Content of {file_path} does not match the expected audit report."

def test_redacted_dump_content():
    file_path = "/home/user/redacted_dump.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_content = """HTTP/1.1 200 OK
Date: Mon, 23 May 2023 22:38:34 GMT
Set-Cookie: session=REDACTED; HttpOnly
Authorization: Bearer REDACTED
X-Crypto-Payload: 1234567890abcdef1234567890abcdef
Set-Cookie: tracking=foo; Secure; HttpOnly
X-Crypto-Payload: abcdef1234567890deadbeefcafebabe
Set-Cookie: session=REDACTED; Path=/
X-Crypto-Payload: 0000000000000000111111111111111122222222222222220000000000000000
Content-Type: application/json
Authorization: Basic dXNlcjpwYXNz
Set-Cookie: prefs=darkmode; Secure
"""

    with open(file_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), f"Content of {file_path} does not match the expected redacted log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
