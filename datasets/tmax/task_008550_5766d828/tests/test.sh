#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import math
import pytest

EXPECTED_RAW_LOG = """2023-11-01 [INFO] pos: <12.0, 5.0, 0.0> - signal stable
2023-11-02 [WARN] pos: ( 3.0, 4.0, 12.0 ) - signal weak
2023-11-03 [DEBUG] position=[0.0, 8.0, 6.0]
2023-11-04 [INFO] coords=2.0, -2.0, 1.0
2023-11-05 [ERROR] loc:< -6.0 , 0.0 , 8.0 >
"""

def test_processed_sensors_csv_exists():
    """Verify that the processed CSV file exists."""
    output_path = "/home/user/processed_sensors.csv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_raw_sensor_log_unchanged():
    """Ensure the writable input fixture was not altered to weaken verification."""
    raw_log_path = "/home/user/raw_sensors.log"
    assert os.path.isfile(raw_log_path), f"The input file {raw_log_path} is missing."
    with open(raw_log_path, "r") as f:
        actual_raw_log = f.read()
    assert actual_raw_log == EXPECTED_RAW_LOG, "The input sensor log was modified."

def test_processed_sensors_csv_content():
    """Verify that the processed CSV file contains the correctly computed and formatted values."""
    raw_log_path = "/home/user/raw_sensors.log"
    assert os.path.isfile(raw_log_path), f"The input file {raw_log_path} is missing."

    expected_lines = []
    with open(raw_log_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue

            # Extract all numbers (integers or floats, positive or negative)
            matches = re.findall(r'-?\d+\.\d+|-?\d+', line)

            # The spatial coordinates (x, y, z) are the last 3 numbers in each log line
            if len(matches) < 3:
                continue

            x, y, z = map(float, matches[-3:])

            # Calculate L2 norm
            norm = math.sqrt(x*x + y*y + z*z)

            # Normalize vector
            if norm == 0:
                nx, ny, nz = 0.0, 0.0, 0.0
            else:
                nx = x / norm
                ny = y / norm
                nz = z / norm

            # Calculate Euclidean distance to reference vector (1.0, 0.0, 0.0)
            dx = nx - 1.0
            dy = ny - 0.0
            dz = nz - 0.0
            dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            # Format to exactly 4 decimal places
            expected_line = f"{x:.4f},{y:.4f},{z:.4f},{nx:.4f},{ny:.4f},{nz:.4f},{dist:.4f}"
            expected_lines.append(expected_line)

    assert expected_lines, "The input sensor log produced no expected rows."

    processed_csv_path = "/home/user/processed_sensors.csv"
    with open(processed_csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} rows in the output CSV, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Row {i+1} does not match the expected output.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
