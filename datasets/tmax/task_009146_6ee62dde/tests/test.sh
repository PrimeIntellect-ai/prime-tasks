#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def test_params_json():
    """Verify that params.json exists and contains the correct hyperparameters."""
    params_path = '/home/user/params.json'
    assert os.path.isfile(params_path), f"File not found: {params_path}"

    with open(params_path, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{params_path} is not a valid JSON file."

    expected_params = {"a": 2, "b": 3, "c": 5}
    assert params == expected_params, f"Expected parameters {expected_params}, but got {params}"

def test_new_training_data_csv():
    """Verify that new_training_data.csv exists, has the correct header, and contains the exact expected data."""
    csv_path = '/home/user/new_training_data.csv'
    assert os.path.isfile(csv_path), f"File not found: {csv_path}"

    a, b, c = 2, 3, 5

    expected_rows = [['x', 'y']]
    for i in range(100, 200):
        x = i * 0.1
        y = math.sin(a * x) + b * math.cos(c * x)
        expected_rows.append([f"{x:.1f}", f"{y:.4f}"])

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "The CSV file is empty."
    assert actual_rows[0] == expected_rows[0], f"Expected header {expected_rows[0]}, got {actual_rows[0]}"
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), got {len(actual_rows)}"

    for idx, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {idx+1} mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
