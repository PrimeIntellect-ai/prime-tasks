#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_final_csv_exists_and_content():
    expected_filepath = "/home/user/summary/critical_sensors.csv"

    assert os.path.isfile(expected_filepath), f"The file {expected_filepath} does not exist. The task is incomplete."

    expected_content = (
        "timestamp,sensor_id,value,status\n"
        "2023-10-01T09:22:00,S05,88.8,CRITICAL\n"
        "2023-10-01T10:01:00,S01,99.9,CRITICAL\n"
        "2023-10-01T11:34:00,S03,105.2,CRITICAL\n"
        "2023-10-01T11:34:00,S03,105.2,CRITICAL\n"
    )

    with open(expected_filepath, 'r') as f:
        actual_content = f.read()

    # Normalize line endings to avoid issues with Windows/Linux newline differences
    actual_content = actual_content.replace('\r\n', '\n').strip() + '\n'
    expected_content = expected_content.strip() + '\n'

    assert actual_content == expected_content, (
        f"The content of {expected_filepath} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
