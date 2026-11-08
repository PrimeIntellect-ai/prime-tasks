#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
import pytest
from collections import defaultdict
from datetime import datetime

def parse_time_to_bucket(ts_str):
    # e.g., '2023-10-01T12:05:23Z' -> '2023-10-01T12:05:00Z'
    dt = datetime.strptime(ts_str, '%Y-%m-%dT%H:%M:%SZ')
    bucket_dt = dt.replace(second=0, microsecond=0)
    return bucket_dt.strftime('%Y-%m-%dT%H:%M:%SZ')

def compute_expected_aggregations(csv_path):
    # Grouping structure: bucket -> sensor_id -> list of accepted (x, y)
    buckets = defaultdict(lambda: defaultdict(list))

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            bucket = parse_time_to_bucket(row['timestamp'])
            sensor_id = row['sensor_id']
            x = float(row['x'])
            y = float(row['y'])

            accepted_points = buckets[bucket][sensor_id]
            is_duplicate = False
            for (ax, ay) in accepted_points:
                dist = math.sqrt((x - ax)**2 + (y - ay)**2)
                if dist <= 0.1:
                    is_duplicate = True
                    break

            if not is_duplicate:
                accepted_points.append((x, y))

    expected_output = []
    for bucket in sorted(buckets.keys()):
        for sensor_id in sorted(buckets[bucket].keys()):
            points = buckets[bucket][sensor_id]
            if not points:
                continue
            mean_x = round(sum(p[0] for p in points) / len(points), 4)
            mean_y = round(sum(p[1] for p in points) / len(points), 4)
            expected_output.append({
                "bucket": bucket,
                "sensor_id": sensor_id,
                "mean_x": mean_x,
                "mean_y": mean_y
            })

    return expected_output

def test_final_json_output():
    csv_path = '/home/user/raw_sensor_data.csv'
    json_path = '/home/user/aggregated_output.json'

    assert os.path.exists(csv_path), f"Input CSV file is missing: {csv_path}"
    assert os.path.exists(json_path), f"Output JSON file is missing: {json_path}"

    expected_data = compute_expected_aggregations(csv_path)

    try:
        with open(json_path, 'r') as f:
            actual_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON output at {json_path}: {e}")

    assert isinstance(actual_data, list), f"Expected JSON root to be a list, but got {type(actual_data).__name__}"

    # Check length
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} aggregated records, but found {len(actual_data)}."
    )

    # Check ordering and exact values
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Expected item at index {i} to be a dictionary."

        # Check keys
        for key in ["bucket", "sensor_id", "mean_x", "mean_y"]:
            assert key in actual, f"Missing key '{key}' in record at index {i}."

        assert actual["bucket"] == expected["bucket"], f"Bucket mismatch at index {i}. Expected {expected['bucket']}, got {actual['bucket']}."
        assert actual["sensor_id"] == expected["sensor_id"], f"Sensor ID mismatch at index {i}. Expected {expected['sensor_id']}, got {actual['sensor_id']}."

        # Check values with small tolerance for float representations, though rounding should make exact equality possible
        assert abs(actual["mean_x"] - expected["mean_x"]) < 1e-5, f"mean_x mismatch at index {i}. Expected {expected['mean_x']}, got {actual['mean_x']}."
        assert abs(actual["mean_y"] - expected["mean_y"]) < 1e-5, f"mean_y mismatch at index {i}. Expected {expected['mean_y']}, got {actual['mean_y']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
