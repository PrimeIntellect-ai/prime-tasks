#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from datetime import datetime, timezone
import pytest

def parse_timestamp(ts_str):
    try:
        # Try parsing as float (unix epoch)
        return int(float(ts_str))
    except ValueError:
        # Parse as datetime string
        dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())

def compute_expected_output():
    incoming_dir = '/home/user/incoming'
    if not os.path.isdir(incoming_dir):
        return []

    long_format = []

    for filename in os.listdir(incoming_dir):
        filepath = os.path.join(incoming_dir, filename)

        # Try reading with utf-8, fallback to iso-8859-1
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            with open(filepath, 'r', encoding='iso-8859-1') as f:
                content = f.read()

        reader = csv.DictReader(content.strip().split('\n'))

        for row in reader:
            try:
                cpu = float(row['cpu'])
                mem = float(row['mem'])
            except (ValueError, KeyError):
                continue

            if cpu < 0 or mem < 0:
                continue

            ts = parse_timestamp(row['timestamp'])
            region = row['region']

            long_format.append({'ts': ts, 'region': region, 'metric': 'cpu', 'val': cpu})
            long_format.append({'ts': ts, 'region': region, 'metric': 'mem', 'val': mem})

    # Sort by region, metric_name, timestamp
    long_format.sort(key=lambda x: (x['region'], x['metric'], x['ts']))

    # Calculate rolling average
    expected_rows = []

    # Group by region and metric
    from itertools import groupby

    for (region, metric), group in groupby(long_format, key=lambda x: (x['region'], x['metric'])):
        items = list(group)
        for i, item in enumerate(items):
            if i == 0:
                rolling_avg = item['val']
            else:
                rolling_avg = (item['val'] + items[i-1]['val']) / 2.0

            expected_rows.append([
                str(item['ts']),
                item['region'],
                item['metric'],
                f"{item['val']:.1f}",
                f"{rolling_avg:.1f}"
            ])

    return expected_rows

def test_etl_output_exists():
    """Test that the ETL output file exists."""
    assert os.path.isfile('/home/user/etl_output.csv'), "The file /home/user/etl_output.csv does not exist."

def test_etl_output_content():
    """Test that the ETL output file contains the correctly processed data."""
    output_path = '/home/user/etl_output.csv'

    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    expected_rows = compute_expected_output()

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but found {len(actual_rows)} rows in the output file."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
