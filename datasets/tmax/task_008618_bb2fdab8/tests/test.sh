#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
from collections import defaultdict

def test_output_file_exists():
    """Check if the output directory and file exist."""
    output_file = "/home/user/time_series_out/daily_averages.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Expected {output_file} to be a file."

def test_output_file_contents():
    """Derive the expected output from the input files and compare it with the actual output."""
    input_csv = "/home/user/time_series_in/batch_alpha.csv"
    input_jsonl = "/home/user/time_series_in/batch_beta.jsonl"
    output_file = "/home/user/time_series_out/daily_averages.csv"

    assert os.path.exists(input_csv), f"Input file {input_csv} is missing."
    assert os.path.exists(input_jsonl), f"Input file {input_jsonl} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # 1. Read input data
    records = []
    with open(input_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            records.append({
                'timestamp': row['timestamp'],
                'sensor_id': row['sensor_id'],
                'value': float(row['value']),
                'etl_run_id': int(row['etl_run_id'])
            })

    with open(input_jsonl, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                records.append({
                    'timestamp': data['timestamp'],
                    'sensor_id': data['sensor_id'],
                    'value': float(data['value']),
                    'etl_run_id': int(data['etl_run_id'])
                })

    # 2. Deduplicate: keep highest etl_run_id for (timestamp, sensor_id)
    dedup_map = {}
    for r in records:
        key = (r['timestamp'], r['sensor_id'])
        if key not in dedup_map or r['etl_run_id'] > dedup_map[key]['etl_run_id']:
            dedup_map[key] = r

    # 3. Aggregate: daily average value per sensor_id
    agg_map = defaultdict(list)
    for key, r in dedup_map.items():
        date = r['timestamp'][:10]
        sensor_id = r['sensor_id']
        agg_map[(date, sensor_id)].append(r['value'])

    # 4. Format and sort expected results
    expected_rows = []
    for (date, sensor_id), values in agg_map.items():
        avg_val = sum(values) / len(values)
        # Round to exactly 2 decimal places
        avg_val_str = f"{round(avg_val, 2):.2f}"
        expected_rows.append((date, sensor_id, avg_val_str))

    expected_rows.sort(key=lambda x: (x[0], x[1]))

    # 5. Read actual output
    actual_rows = []
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['date', 'sensor_id', 'avg_value'], \
            f"Expected header ['date', 'sensor_id', 'avg_value'], got {header}"
        for row in reader:
            if row:
                actual_rows.append(tuple(row))

    # 6. Compare actual with expected
    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows of data, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, got {actual}. Ensure correct deduplication, aggregation, and sorting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
