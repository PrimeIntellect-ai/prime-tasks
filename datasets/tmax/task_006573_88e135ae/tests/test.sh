#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
from collections import defaultdict

def compute_expected_output(input_file):
    if not os.path.exists(input_file):
        return []

    # 1. Cleaning
    valid_timestamp_re = re.compile(r'^\d{10}$')
    valid_temp_re = re.compile(r'^-?\d+(\.\d+)?$')

    cleaned_data = []
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|')
            if len(parts) != 3:
                continue
            sensor_id, timestamp, temperature = parts

            if not valid_timestamp_re.match(timestamp):
                continue
            if not valid_temp_re.match(temperature):
                continue

            cleaned_data.append((sensor_id, int(timestamp), float(temperature)))

    # 2. Deduplication
    dedup = {}
    for sensor_id, timestamp, temperature in cleaned_data:
        key = (sensor_id, timestamp)
        if key not in dedup or temperature > dedup[key]:
            dedup[key] = temperature

    # 3. Time-based Bucketing & Aggregation
    buckets = defaultdict(lambda: defaultdict(list))
    for (sensor_id, timestamp), temperature in dedup.items():
        bucket_start = (timestamp // 3600) * 3600
        buckets[sensor_id][bucket_start].append(temperature)

    # 4. Resampling / Gap-Filling
    expected_rows = []
    for sensor_id in sorted(buckets.keys()):
        sensor_buckets = buckets[sensor_id]
        min_bucket = min(sensor_buckets.keys())
        max_bucket = max(sensor_buckets.keys())

        for bucket_start in range(min_bucket, max_bucket + 3600, 3600):
            if bucket_start in sensor_buckets:
                temps = sensor_buckets[bucket_start]
                avg_temp = sum(temps) / len(temps)
            else:
                avg_temp = 0.0

            # Format to 1 decimal place
            formatted_temp = f"{avg_temp:.1f}"
            expected_rows.append(f"{sensor_id},{bucket_start},{formatted_temp}")

    return expected_rows

def test_etl_output_exists():
    assert os.path.exists("/home/user/etl_output.csv"), "The output file /home/user/etl_output.csv was not found."

def test_etl_output_correctness():
    input_file = "/home/user/sensor_data.txt"
    output_file = "/home/user/etl_output.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing, cannot verify."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    expected_lines = compute_expected_output(input_file)

    with open(output_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Output in {output_file} does not match expected results.\n"
        f"Expected {len(expected_lines)} lines, got {len(actual_lines)} lines.\n"
        f"First few expected: {expected_lines[:3]}\n"
        f"First few actual: {actual_lines[:3]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
