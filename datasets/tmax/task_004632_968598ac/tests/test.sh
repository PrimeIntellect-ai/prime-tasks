#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import re
import pytest

def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.txt"

    assert os.path.isfile(report_path), f"The audit report file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, f"The file {report_path} must contain at least two lines."

    cwe_line = lines[0]
    token_line = lines[1]

    # Check CWE line
    assert re.match(r"^CWE:\s*CWE-(798|321)$", cwe_line, re.IGNORECASE), \
        f"The first line must specify the correct CWE ID (CWE-798 or CWE-321). Found: {cwe_line}"

    # Check Token line
    salt = "SuperS3cr3tS@lt99"
    username = "admin"
    expected_token = hashlib.sha256((username + salt).encode('utf-8')).hexdigest()

    expected_token_line = f"Admin_Token: {expected_token}"
    assert token_line == expected_token_line, \
        f"The second line must contain the correct Admin_Token. Expected: {expected_token_line}, Found: {token_line}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
