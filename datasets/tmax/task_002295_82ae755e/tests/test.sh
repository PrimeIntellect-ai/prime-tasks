#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_deadlock_report_exists():
    report_path = '/home/user/deadlock_report.txt'
    assert os.path.isfile(report_path), f"The output file {report_path} was not created."

def test_deadlock_report_content():
    report_path = '/home/user/deadlock_report.txt'
    assert os.path.isfile(report_path), f"The output file {report_path} was not created."

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_cycle = "P_COMPLIANCE_AUDIT,P_X1,P_Y1,P_X2,P_Y2,P_COMPLIANCE_AUDIT"

    assert content == expected_cycle, (
        f"The deadlock report content is incorrect.\n"
        f"Expected: {expected_cycle}\n"
        f"Found:    {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
