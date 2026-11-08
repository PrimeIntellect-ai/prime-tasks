#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_security_report_exists_and_correct():
    report_path = "/home/user/security_report.txt"
    assert os.path.isfile(report_path), f"The final report file {report_path} is missing."

    expected_content = """REPORT START
[2023-10-01T09:50:00Z] malicious_intent_sqli
Paths: /api/v1/users, /login
---
[2023-10-01T10:10:00Z] malicious_intent_xss
Paths: /api/v1/search
---
[2023-10-01T10:20:00Z] malicious_intent_rce
Paths: /admin/dashboard, /api/v1/admin
REPORT END"""

    with open(report_path, 'r') as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"The content of {report_path} does not match the expected format or findings.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
