#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_report_exists():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist. The task requires saving the results to this file."
    assert os.path.isfile(report_path), f"Path {report_path} is not a file."

def test_report_contents():
    report_path = "/home/user/report.txt"
    if not os.path.exists(report_path):
        return # Handled by test_report_exists

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 4, f"Expected at least 4 lines in {report_path}, got {len(lines)}."

    # The expected values are based on the fixed random seed used in the setup.
    expected_alpha = "Mean Alpha: 55.4528"
    expected_beta = "Mean Beta: 50.1260"
    expected_tstat = "T-statistic: 8.5255"
    expected_pval = "P-value: 0.0000"

    assert expected_alpha in lines[0], f"Line 1 expected to contain '{expected_alpha}', got '{lines[0]}'"
    assert expected_beta in lines[1], f"Line 2 expected to contain '{expected_beta}', got '{lines[1]}'"
    assert expected_tstat in lines[2], f"Line 3 expected to contain '{expected_tstat}', got '{lines[2]}'"
    assert expected_pval in lines[3], f"Line 4 expected to contain '{expected_pval}', got '{lines[3]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
