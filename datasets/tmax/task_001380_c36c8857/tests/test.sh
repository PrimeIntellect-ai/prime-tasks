#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
from collections import defaultdict

def test_aggregated_csv_exists_and_correct():
    output_path = '/home/user/etl_output/aggregated.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    # Parse stream1.csv
    stream1_path = '/home/user/raw_data/stream1.csv'
    assert os.path.isfile(stream1_path), f"Input file {stream1_path} is missing."

    records = set()
    with open(stream1_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) == 3:
                ts, sensor, temp_str = row
                if temp_str.strip():
                    records.add((ts, sensor, float(temp_str)))

    # Parse stream2.jsonl
    stream2_path = '/home/user/raw_data/stream2.jsonl'
    assert os.path.isfile(stream2_path), f"Input file {stream2_path} is missing."

    with open(stream2_path, 'r') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                ts = data.get('ts')
                sensor = data.get('id')
                temp = data.get('v')
                if temp is not None:
                    records.add((ts, sensor, float(temp)))

    # Bucket and aggregate
    buckets = defaultdict(list)
    for ts, sensor, temp in records:
        # ts format: 2023-11-01T08:15:30Z -> 2023-11-01T08:00:00Z
        bucket = ts[:14] + "00:00Z"
        buckets[(bucket, sensor)].append(temp)

    expected_rows = []
    for (bucket, sensor), temps in buckets.items():
        avg_temp = sum(temps) / len(temps)
        expected_rows.append((bucket, sensor, f"{avg_temp:.2f}"))

    expected_rows.sort(key=lambda x: (x[0], x[1]))

    # Read actual output
    actual_rows = []
    with open(output_path, 'r') as f:
        reader = csv.reader(f)
        actual_header = next(reader, None)
        assert actual_header == ['bucket', 'sensor', 'avg_temp'], "Output CSV header is incorrect."
        for row in reader:
            if row:
                actual_rows.append(tuple(row))

    assert actual_rows == expected_rows, f"Output CSV content does not match expected.\nExpected: {expected_rows}\nActual: {actual_rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
