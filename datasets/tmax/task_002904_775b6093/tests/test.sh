#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_processed_sensors_file_exists():
    file_path = "/home/user/processed_sensors.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. The task is incomplete."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_processed_sensors_content():
    file_path = "/home/user/processed_sensors.csv"
    expected_content = """bucket_timestamp,sensor_id,temperature
1600002000,A,21.0
1600002300,A,22.0
1600002600,A,22.0
1600002900,A,25.0
1600002300,B,15.0
1600002600,B,16.5
1600002900,B,17.0"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {file_path} does not match the expected final state. Found:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
