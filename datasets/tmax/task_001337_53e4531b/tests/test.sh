#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def test_latency_anomalies_csv_exists():
    """Verify that the output CSV file exists."""
    file_path = "/home/user/latency_anomalies.csv"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    assert os.path.isfile(file_path), f"Path is not a file: {file_path}"

def test_latency_anomalies_content():
    """Verify the contents of the generated CSV file by recomputing the expected output."""
    input_file = "/home/user/access_logs.jsonl"
    output_file = "/home/user/latency_anomalies.csv"

    assert os.path.exists(input_file), f"Missing input file: {input_file}"
    assert os.path.exists(output_file), f"Missing output file: {output_file}"

    expected_rows = []
    window = []

    with open(input_file, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f):
            if not line.strip():
                continue

            record = json.loads(line)
            latency = record['latency_ms']

            if i > 0:
                # Calculate rolling average of previous requests (up to 50)
                rolling_avg = sum(window) / len(window)

                # Check for anomaly
                if latency > 3 * rolling_avg:
                    # Mask IP
                    ip_parts = record['ip'].split('.')
                    ip_parts[-1] = 'XXX'
                    masked_ip = '.'.join(ip_parts)

                    expected_rows.append({
                        'timestamp': record['timestamp'],
                        'masked_ip': masked_ip,
                        'latency_ms': str(latency),
                        'rolling_avg': f"{rolling_avg:.2f}"
                    })

            # Update window
            window.append(latency)
            if len(window) > 50:
                window.pop(0)

    # Read actual output
    actual_rows = []
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'masked_ip', 'latency_ms', 'rolling_avg'], \
            f"Incorrect CSV header. Expected ['timestamp', 'masked_ip', 'latency_ms', 'rolling_avg'], got {reader.fieldnames}"
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} anomaly rows, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual['timestamp'] == expected['timestamp'], f"Row {i+1}: timestamp mismatch. Expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['masked_ip'] == expected['masked_ip'], f"Row {i+1}: masked_ip mismatch. Expected {expected['masked_ip']}, got {actual['masked_ip']}"
        assert actual['latency_ms'] == expected['latency_ms'], f"Row {i+1}: latency_ms mismatch. Expected {expected['latency_ms']}, got {actual['latency_ms']}"
        assert actual['rolling_avg'] == expected['rolling_avg'], f"Row {i+1}: rolling_avg mismatch. Expected {expected['rolling_avg']}, got {actual['rolling_avg']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
