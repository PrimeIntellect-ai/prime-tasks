#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re

def compute_expected(input_file):
    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    valid_rows = []
    for row in rows:
        # Check empty
        if any(not v.strip() for v in row.values()):
            continue

        try:
            temp = float(row['temperature'])
            cpu = float(row['cpu_load'])
        except ValueError:
            continue

        if not (0.0 <= temp <= 120.0):
            continue
        if not (0.0 <= cpu <= 100.0):
            continue

        # Extract date
        ts = row['timestamp']
        if 'T' not in ts:
            continue
        date = ts.split('T')[0]

        # Normalize status
        status = row['status_msg'].lower()
        status = re.sub(r'[^a-z0-9 ]', '', status)
        status = re.sub(r' +', ' ', status).strip()

        valid_rows.append({
            'timestamp': ts,
            'date': date,
            'server_id': row['server_id'],
            'temperature': row['temperature'],
            'cpu_load': row['cpu_load'],
            'normalized_status': status
        })

    # Sort by timestamp to guarantee earliest is first
    valid_rows.sort(key=lambda x: x['timestamp'])

    kept = {}
    for row in valid_rows:
        key = (row['date'], row['server_id'])
        if key not in kept:
            kept[key] = row

    # Sort output by date asc, server_id asc
    final_rows = list(kept.values())
    final_rows.sort(key=lambda x: (x['date'], x['server_id']))

    return final_rows

def test_processed_metrics_file_exists():
    """Check if the output processed_metrics.csv file exists."""
    output_file = '/home/user/processed_metrics.csv'
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

def test_processed_metrics_content():
    """Check if the output processed_metrics.csv file has the correct content."""
    input_file = '/home/user/metrics.csv'
    output_file = '/home/user/processed_metrics.csv'

    assert os.path.exists(input_file), f"Input file {input_file} is missing, cannot compute expected output."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    expected_data = compute_expected(input_file)
    expected_header = ['date', 'server_id', 'temperature', 'cpu_load', 'normalized_status']

    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            actual_header = []
        actual_rows = list(reader)

    assert actual_header == expected_header, f"Expected header {expected_header}, but got {actual_header}"
    assert len(actual_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_data)):
        expected_row = [
            expected['date'],
            expected['server_id'],
            expected['temperature'],
            expected['cpu_load'],
            expected['normalized_status']
        ]
        assert actual == expected_row, f"Row {i+1} mismatch. Expected: {expected_row}, Got: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
