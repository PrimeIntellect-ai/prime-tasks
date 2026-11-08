#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from datetime import datetime, timezone
from collections import defaultdict

def test_summary_csv_exists_and_correct():
    output_file = '/home/user/summary.csv'
    eu_file = '/home/user/branch_eu.csv'
    na_file = '/home/user/branch_na.csv'

    assert os.path.exists(output_file), f"Output file missing: {output_file}"
    assert os.path.exists(eu_file), f"Input file missing: {eu_file}"
    assert os.path.exists(na_file), f"Input file missing: {na_file}"

    # Recompute expected data from source files
    buckets = defaultdict(list)

    # Parse EU data
    with open(eu_file, 'r', encoding='iso-8859-1') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Format: 2023-10-01 12:15:00+02:00
            # Python 3.7+ supports %z parsing for +HH:MM
            dt_str = row['Time']
            # Fix timezone format for older python versions if needed, but %z handles +02:00 in 3.7+
            dt = datetime.strptime(dt_str, '%Y-%m-%d %H:%M:%S%z')
            dt_utc = dt.astimezone(timezone.utc)
            bucket = dt_utc.strftime('%Y-%m-%d %H:00:00')
            buckets[bucket].append(float(row['Value']))

    # Parse NA data
    with open(na_file, 'r', encoding='utf-16') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Format: 10/01/2023 06:30:00 AM-04:00
            dt_str = row['Timestamp']
            dt = datetime.strptime(dt_str, '%m/%d/%Y %I:%M:%S %p%z')
            dt_utc = dt.astimezone(timezone.utc)
            bucket = dt_utc.strftime('%Y-%m-%d %H:00:00')
            buckets[bucket].append(float(row['Measurement']))

    expected_rows = []
    for bucket in sorted(buckets.keys()):
        vals = buckets[bucket]
        mean_val = sum(vals) / len(vals)
        expected_rows.append({'bucket_utc': bucket, 'mean_value': f"{mean_val:.2f}"})

    # Read the actual output file
    try:
        with open(output_file, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"Output file {output_file} is not valid UTF-8 encoded.")

    # Parse actual output
    actual_rows = []
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['bucket_utc', 'mean_value'], \
            f"Expected columns ['bucket_utc', 'mean_value'], got {reader.fieldnames}"
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)} rows in summary.csv."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert expected['bucket_utc'] == actual['bucket_utc'], \
            f"Row {i+1}: Expected bucket_utc '{expected['bucket_utc']}', got '{actual['bucket_utc']}'"
        assert expected['mean_value'] == actual['mean_value'], \
            f"Row {i+1}: Expected mean_value '{expected['mean_value']}', got '{actual['mean_value']}'"

    # Also verify that the file is strictly ordered by bucket_utc chronologically
    actual_buckets = [row['bucket_utc'] for row in actual_rows]
    assert actual_buckets == sorted(actual_buckets), "The output CSV is not sorted chronologically by bucket_utc."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
