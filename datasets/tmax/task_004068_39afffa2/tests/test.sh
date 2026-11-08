#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_processed_sensors_exists():
    """Check if the processed CSV file was created."""
    file_path = "/home/user/processed_sensors.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. The task is not complete."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_processed_sensors_content():
    """Verify the content of the processed CSV file matches the expected output exactly."""
    file_path = "/home/user/processed_sensors.csv"

    expected_content = """TIMESTAMP,SENSOR_NAME,TEMP,SMA_3
2023-10-01 10:00,SENSOR_X,45.0,45.00
2023-10-01 10:05,SENSOR_X,46.0,45.50
2023-10-01 10:10,SENSOR_X,47.0,46.00
2023-10-01 10:15,SENSOR_X,48.0,47.00
2023-10-01 10:20,SENSOR_X,49.0,48.00
2023-10-01 10:00,SENSOR_Y,50.0,50.00
2023-10-01 10:05,SENSOR_Y,49.0,49.50
2023-10-01 10:10,SENSOR_Y,50.0,49.67
2023-10-01 10:15,SENSOR_Y,51.0,50.00
2023-10-01 10:20,SENSOR_Y,52.0,51.00
2023-10-01 10:00,SENSOR_Z,40.0,40.00
2023-10-01 10:05,SENSOR_Z,41.0,40.50
2023-10-01 10:10,SENSOR_Z,42.0,41.00
2023-10-01 10:15,SENSOR_Z,40.0,41.00
2023-10-01 10:20,SENSOR_Z,39.0,40.33"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    # Split into lines for better error reporting
    actual_lines = content.splitlines()
    expected_lines = expected_content.splitlines()

    assert len(actual_lines) == len(expected_lines), (
        f"Line count mismatch. Expected {len(expected_lines)} lines, but got {len(actual_lines)} lines."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}:\n"
            f"Expected: {expected}\n"
            f"Actual  : {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
