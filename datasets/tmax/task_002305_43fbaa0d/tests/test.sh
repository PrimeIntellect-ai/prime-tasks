#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_vulnerability_report():
    report_path = "/home/user/vulnerability_report.txt"

    assert os.path.exists(report_path), f"The file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a regular file."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_token = "TOKEN_77X92_BETA_LEAK"
    expected_cn = "vulnerable.localnetwork.com"

    token_found = False
    cn_found = False

    for line in lines:
        if line.startswith("TOKEN="):
            token_val = line.split("=", 1)[1]
            assert token_val == expected_token, f"Expected TOKEN={expected_token}, but found TOKEN={token_val}"
            token_found = True
        elif line.startswith("CN="):
            cn_val = line.split("=", 1)[1]
            assert cn_val == expected_cn, f"Expected CN={expected_cn}, but found CN={cn_val}"
            cn_found = True

    assert token_found, "The report file is missing the 'TOKEN=' line."
    assert cn_found, "The report file is missing the 'CN=' line."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
