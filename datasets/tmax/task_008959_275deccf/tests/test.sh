#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import math

def test_clean_data_csv():
    raw_path = '/home/user/raw_data.csv'
    clean_path = '/home/user/clean_data.csv'

    assert os.path.exists(clean_path), f"File {clean_path} is missing."

    # Read raw data and determine expected valid rows
    with open(raw_path, 'r', newline='') as f:
        reader = csv.reader(f)
        raw_data = list(reader)

    header = raw_data[0]
    expected_clean = [header]
    for row in raw_data[1:]:
        if len(row) != 3:
            continue
        try:
            int(row[0])
            float(row[1])
            float(row[2])
            expected_clean.append(row)
        except ValueError:
            pass

    with open(clean_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_clean = list(reader)

    assert len(actual_clean) == len(expected_clean), f"Expected {len(expected_clean)} rows in clean_data.csv, got {len(actual_clean)}."

    # Check headers and ids
    expected_ids = [row[0] for row in expected_clean]
    actual_ids = [row[0] for row in actual_clean]
    assert actual_ids == expected_ids, f"Expected IDs {expected_ids}, got {actual_ids}."

    # Check values as floats
    for exp, act in zip(expected_clean[1:], actual_clean[1:]):
        assert int(exp[0]) == int(act[0]), f"ID mismatch: expected {exp[0]}, got {act[0]}"
        assert math.isclose(float(exp[1]), float(act[1]), rel_tol=1e-5), f"val_x mismatch for ID {exp[0]}: expected {exp[1]}, got {act[1]}"
        assert math.isclose(float(exp[2]), float(act[2]), rel_tol=1e-5), f"val_y mismatch for ID {exp[0]}: expected {exp[2]}, got {act[2]}"

def test_metrics_json():
    clean_path = '/home/user/clean_data.csv'
    metrics_path = '/home/user/metrics.json'

    assert os.path.exists(metrics_path), f"File {metrics_path} is missing."
    assert os.path.exists(clean_path), f"File {clean_path} is missing."

    # Calculate expected statistics based on the cleaned data
    with open(clean_path, 'r', newline='') as f:
        reader = csv.reader(f)
        clean_data = list(reader)

    val_x = [float(row[1]) for row in clean_data[1:]]
    val_y = [float(row[2]) for row in clean_data[1:]]

    n = len(val_x)
    assert n > 1, "Not enough valid rows to compute statistics."

    mean_x = sum(val_x) / n
    mean_y = sum(val_y) / n

    var_x = sum((x - mean_x)**2 for x in val_x) / (n - 1)
    stddev_x = math.sqrt(var_x)

    covar = sum((x - mean_x)*(y - mean_y) for x, y in zip(val_x, val_y)) / (n - 1)
    var_y = sum((y - mean_y)**2 for y in val_y) / (n - 1)
    stddev_y = math.sqrt(var_y)

    correlation = covar / (stddev_x * stddev_y)

    ci_lower_x = mean_x - 1.96 * (stddev_x / math.sqrt(n))
    ci_upper_x = mean_x + 1.96 * (stddev_x / math.sqrt(n))

    expected_metrics = {
        "correlation": round(correlation, 4),
        "mean_x": round(mean_x, 4),
        "ci_lower_x": round(ci_lower_x, 4),
        "ci_upper_x": round(ci_upper_x, 4)
    }

    with open(metrics_path, 'r') as f:
        try:
            actual_metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {metrics_path} is not valid JSON."

    expected_keys = set(expected_metrics.keys())
    actual_keys = set(actual_metrics.keys())
    assert actual_keys == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {actual_keys}."

    for k, v in expected_metrics.items():
        assert math.isclose(actual_metrics[k], v, abs_tol=0.0002), f"Mismatch for {k}: expected {v}, got {actual_metrics[k]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
