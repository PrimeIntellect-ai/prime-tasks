#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_web_01_report():
    file_path = '/home/user/output/web-01_report.txt'
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

    expected_content = """Host: web-01
Total Windows: 3

Metrics:
Window: 1685581200 | Avg CPU: 50.25 | Max Mem: 2048.0
Window: 1685584800 | Avg CPU: 80.00 | Max Mem: 4096.0
Window: 1685588400 | Avg CPU: 90.50 | Max Mem: 4096.0"""

    with open(file_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {file_path} does not match expected.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )

def test_db_01_report():
    file_path = '/home/user/output/db-01_report.txt'
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

    expected_content = """Host: db-01
Total Windows: 1

Metrics:
Window: 1685581200 | Avg CPU: 12.50 | Max Mem: 8192.0"""

    with open(file_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {file_path} does not match expected.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
