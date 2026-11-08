#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def test_imputed_sensor_data_exists():
    """Verify that the output file exists."""
    assert os.path.isfile("/home/user/imputed_sensor_data.csv"), "The output file /home/user/imputed_sensor_data.csv does not exist."

def test_imputed_sensor_data_content():
    """Verify that the output file contains the correctly imputed data."""
    input_file = "/home/user/sensor_data.csv"
    output_file = "/home/user/imputed_sensor_data.csv"

    assert os.path.isfile(input_file), f"{input_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is missing."

    # Read input data
    with open(input_file, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        input_rows = list(reader)

    valid_points = []
    for row in input_rows:
        if row[3].strip() != "":
            valid_points.append({
                'id': row[0],
                'x': float(row[1]),
                'y': float(row[2]),
                'value': float(row[3])
            })

    expected_output = [header]
    for row in input_rows:
        if row[3].strip() != "":
            expected_output.append(row)
        else:
            x = float(row[1])
            y = float(row[2])

            # Calculate distances to all valid points
            distances = []
            for vp in valid_points:
                dist = math.hypot(x - vp['x'], y - vp['y'])
                distances.append((dist, vp['value']))

            # Sort by distance and take top 3
            distances.sort(key=lambda item: item[0])
            top3 = distances[:3]

            # Calculate IDW
            num = 0.0
            den = 0.0
            for d, v in top3:
                weight = 1.0 / (d ** 2)
                num += v * weight
                den += weight

            imputed_value = num / den

            # Apply quality gate
            if 10.0 <= imputed_value <= 90.0:
                final_val = f"{imputed_value:.2f}"
            else:
                final_val = "REJECTED"

            expected_output.append([row[0], row[1], row[2], final_val])

    # Read actual output
    with open(output_file, 'r') as f:
        reader = csv.reader(f)
        actual_output = list(reader)

    assert len(actual_output) == len(expected_output), f"Expected {len(expected_output)} rows, but got {len(actual_output)}."

    for i, (actual, expected) in enumerate(zip(actual_output, expected_output)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
