#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Crash Time: 2023-10-24T09:15:15\n"
        "Request ID: 8004\n"
        "Payload: PAYLOAD_X9f823mPq"
    )

    assert content == expected_content, (
        f"The content of {report_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
