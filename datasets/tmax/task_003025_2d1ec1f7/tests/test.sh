#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_report_exists():
    report_path = "/home/user/spectroscopy/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not generated."

def test_report_content():
    expected_path = "/tests/expected_report.txt"
    actual_path = "/home/user/spectroscopy/report.txt"

    assert os.path.isfile(expected_path), f"Expected truth file {expected_path} is missing."
    assert os.path.isfile(actual_path), f"Actual report file {actual_path} is missing."

    with open(expected_path, "r") as f:
        expected_lines = [line.strip() for line in f.read().strip().split('\n')]

    with open(actual_path, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(actual_lines) == len(expected_lines), (
        f"Report has incorrect number of lines. Expected {len(expected_lines)}, got {len(actual_lines)}."
    )

    for i, (expected_line, actual_line) in enumerate(zip(expected_lines, actual_lines)):
        assert actual_line == expected_line, (
            f"Mismatch on line {i+1}.\n"
            f"Expected: {expected_line}\n"
            f"Got:      {actual_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
