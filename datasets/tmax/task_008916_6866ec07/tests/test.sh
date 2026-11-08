#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_report_exists():
    """Verify that the report.txt file was generated."""
    file_path = "/home/user/report.txt"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

def test_report_contents():
    """Verify that the report.txt contains the correct processed data."""
    file_path = "/home/user/report.txt"

    if not os.path.isfile(file_path):
        assert False, f"Cannot check contents because {file_path} does not exist."

    expected_lines = [
        "Lab: alpha | Trials: 2 | Avg: 10.50",
        "Lab: beta | Trials: 3 | Avg: 21.00",
        "Lab: delta | Trials: 2 | Avg: 5.00",
        "Lab: gamma | Trials: 1 | Avg: 15.00"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {file_path} are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
