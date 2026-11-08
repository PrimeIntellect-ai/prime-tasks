#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_audit_report_content():
    report_path = "/home/user/audit_report.txt"
    assert os.path.exists(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "sec_auditor_99:rooster:TOKEN_8a9b2c4d"
    assert content == expected_content, f"Audit report content is incorrect. Expected '{expected_content}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
