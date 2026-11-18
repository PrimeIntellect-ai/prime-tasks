#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_report_exists():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

def test_report_contents():
    report_path = "/home/user/report.txt"
    expected_commit_path = "/tests/commit.txt"
    expected_error_path = "/tests/error.txt"

    assert os.path.isfile(expected_commit_path), f"Expected commit file {expected_commit_path} missing."
    assert os.path.isfile(expected_error_path), f"Expected error file {expected_error_path} missing."

    with open(expected_commit_path, "r") as f:
        expected_commit = f.read().strip()

    with open(expected_error_path, "r") as f:
        expected_error = f.read().strip()

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip() != ""]

    assert len(lines) >= 2, f"Report file {report_path} must contain at least two lines."

    actual_commit = lines[0]
    actual_error = lines[1]

    assert actual_commit == expected_commit, f"Line 1 of report.txt is incorrect. Expected {expected_commit}, got {actual_commit}"
    assert actual_error == expected_error, f"Line 2 of report.txt is incorrect. Expected {expected_error}, got {actual_error}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
