#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_master_log_exists():
    assert os.path.isfile("/home/user/output/master_log.csv"), "/home/user/output/master_log.csv does not exist."

def test_anomaly_file_exists():
    assert os.path.isfile("/home/user/output/anomaly.txt"), "/home/user/output/anomaly.txt does not exist."

def test_anomaly_content():
    with open("/home/user/output/anomaly.txt", "r") as f:
        content = f.read().strip()
    assert content == "2023-10-03", f"Expected anomaly date to be '2023-10-03', but got '{content}'"

def test_master_log_content():
    expected_lines = [
        "date,session_id,status,notes",
        "2023-10-01,1001,SUCCESS,Normal operation",
        "2023-10-01,1002,ERROR,Connection timeout after 30 seconds",
        "2023-10-01,1003,SUCCESS,User logged in",
        "2023-10-02,2001,SUCCESS,File uploaded",
        "2023-10-02,2002,WARNING,Disk space low clean up required immediately",
        "2023-10-02,2003,SUCCESS,Batch job complete",
        "2023-10-03,3001,SUCCESS,Routine check",
        "2023-10-04,4001,SUCCESS,Normal operation",
        "2023-10-04,4002,ERROR,Database locked",
        "2023-10-04,4003,SUCCESS,All clear"
    ]

    with open("/home/user/output/master_log.csv", "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) > 0, "master_log.csv is empty."

    # Check header
    assert actual_lines[0] == expected_lines[0], f"Expected header '{expected_lines[0]}', got '{actual_lines[0]}'"

    # Check total number of lines (1 header + 10 unique data rows)
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)} lines. Did you deduplicate correctly?"

    # Check exact content and order
    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
