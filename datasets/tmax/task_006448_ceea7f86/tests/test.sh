#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest
from collections import defaultdict

def test_rolling_stats_exists():
    """Test that the output CSV file exists."""
    file_path = '/home/user/rolling_stats.csv'
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_rolling_stats_contents():
    """Test that the output CSV file has the correct headers, data, and sorting."""
    input_path = '/home/user/audit_log.csv'
    output_path = '/home/user/rolling_stats.csv'

    assert os.path.exists(input_path), f"Input file {input_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    # Compute expected results from the input file
    server_data = defaultdict(list)
    with open(input_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['Key'] == 'nginx_config':
                timestamp = int(row['Timestamp'])
                server = row['Server']
                value = row['Value']
                # Number of lines is number of newlines + 1
                line_count = value.count('\n') + 1
                server_data[server].append((timestamp, line_count))

    expected_rows = []
    for server in sorted(server_data.keys()):
        # Sort chronologically
        events = sorted(server_data[server], key=lambda x: x[0])
        for i, (ts, lc) in enumerate(events):
            if i == 0:
                moving_avg = float(lc)
            else:
                moving_avg = (lc + events[i-1][1]) / 2.0

            expected_rows.append({
                'Server': server,
                'Timestamp': str(ts),
                'LineCount': str(lc),
                'MovingAvg': f"{moving_avg:.1f}"
            })

    # Read actual results
    actual_rows = []
    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ["Server", "Timestamp", "LineCount", "MovingAvg"], \
            f"Output CSV headers are incorrect. Got: {headers}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Row does not have 4 columns: {row}"
            actual_rows.append({
                'Server': row[0],
                'Timestamp': row[1],
                'LineCount': row[2],
                'MovingAvg': row[3]
            })

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
