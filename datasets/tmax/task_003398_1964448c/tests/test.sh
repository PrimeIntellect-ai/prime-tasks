#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

def test_pipeline_results_json_exists():
    file_path = "/home/user/pipeline_results.json"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

def test_pipeline_results_content():
    json_path = "/home/user/pipeline_results.json"
    csv_path = "/home/user/raw_sensor_data.csv"

    assert os.path.isfile(json_path), f"The output file {json_path} does not exist."
    assert os.path.isfile(csv_path), f"The input file {csv_path} does not exist."

    # Parse the generated JSON
    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} is not valid JSON.")

    expected_keys = {"train_mean", "train_std", "weight", "bias", "test_first_scaled_reading"}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"The JSON file is missing keys: {missing_keys}"

    # Compute ground truth from CSV
    rows = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_id = float(row['sensor_id'])
            if sensor_id < 1 or sensor_id > 100:
                continue
            if row['reading_value'] != '':
                reading = float(row['reading_value'])
                if reading > 1000.0:
                    continue
            rows.append(row)

    total_valid = len(rows)
    train_count = total_valid * 8 // 10
    train_rows = rows[:train_count]
    test_rows = rows[train_count:]

    # Compute train mean and std
    valid_train_readings = [float(r['reading_value']) for r in train_rows if r['reading_value'] != '']
    train_mean = sum(valid_train_readings) / len(valid_train_readings)

    variance = sum((x - train_mean) ** 2 for x in valid_train_readings) / (len(valid_train_readings) - 1)
    train_std = math.sqrt(variance)

    # Compute OLS on Train
    train_x_scaled = []
    train_y = []
    for r in train_rows:
        val = float(r['reading_value']) if r['reading_value'] != '' else train_mean
        scaled = (val - train_mean) / train_std
        train_x_scaled.append(scaled)
        train_y.append(float(r['target_value']))

    mean_x = sum(train_x_scaled) / len(train_x_scaled)
    mean_y = sum(train_y) / len(train_y)

    cov_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(train_x_scaled, train_y))
    var_x = sum((x - mean_x) ** 2 for x in train_x_scaled)
    weight = cov_xy / var_x
    bias = mean_y - weight * mean_x

    # First test row scaled reading
    first_test_val = float(test_rows[0]['reading_value']) if test_rows[0]['reading_value'] != '' else train_mean
    test_first_scaled = (first_test_val - train_mean) / train_std

    # Expected values rounded to 4 decimals
    expected = {
        "train_mean": round(train_mean, 4),
        "train_std": round(train_std, 4),
        "weight": round(weight, 4),
        "bias": round(bias, 4),
        "test_first_scaled_reading": round(test_first_scaled, 4)
    }

    for key, expected_val in expected.items():
        actual_val = results[key]
        assert isinstance(actual_val, (int, float)), f"Value for {key} should be a float, got {type(actual_val)}."
        assert math.isclose(actual_val, expected_val, abs_tol=1e-4), \
            f"Mismatch for {key}: expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
