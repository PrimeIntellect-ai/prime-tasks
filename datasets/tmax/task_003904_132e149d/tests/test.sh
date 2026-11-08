#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

EXPECTED_OUTPUT = """timestamp,sensor,temperature,rolling_mean
2023-10-01T10:00,Sensor_East,19.00,19.00
2023-10-01T10:05,Sensor_East,19.20,19.10
2023-10-01T10:10,Sensor_East,19.40,19.20
2023-10-01T10:15,Sensor_East,19.60,19.40
2023-10-01T10:20,Sensor_East,19.80,19.60
2023-10-01T10:00,Sensor_North,20.00,20.00
2023-10-01T10:05,Sensor_North,20.50,20.25
2023-10-01T10:10,Sensor_North,21.00,20.50
2023-10-01T10:15,Sensor_North,21.50,21.00
2023-10-01T10:20,Sensor_North,22.00,21.50
2023-10-01T10:00,Sensor_South,22.00,22.00
2023-10-01T10:05,Sensor_South,22.20,22.10
2023-10-01T10:10,Sensor_South,22.40,22.20
2023-10-01T10:15,Sensor_South,22.60,22.40
2023-10-01T10:20,Sensor_South,22.80,22.60"""

def test_processed_file_exists():
    file_path = "/home/user/processed_sensor_data.csv"
    assert os.path.isfile(file_path), f"The processed file does not exist at {file_path}. Did you save it to the correct location?"

def test_processed_file_content():
    file_path = "/home/user/processed_sensor_data.csv"
    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_lines = EXPECTED_OUTPUT.split('\n')
    actual_lines = content.split('\n')

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows (including header), but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}\nCheck sorting, 2-decimal formatting, or calculation logic."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
