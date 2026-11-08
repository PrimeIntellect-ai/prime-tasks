#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
from datetime import datetime
from collections import defaultdict

def parse_timestamp(ts_str):
    ts_str = ts_str.strip()
    try:
        return datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        pass
    try:
        return datetime.strptime(ts_str, "%m/%d/%Y %H:%M:%S")
    except ValueError:
        raise ValueError(f"Unknown timestamp format: {ts_str}")

def derive_expected_data(input_path):
    log_pattern = re.compile(r"^(.*?)\s*\|\s*Task:(.*?)\s*\|\s*Target:(.*?)\s*\|\s*Latency:(\d+)ms$")

    tasks = {}

    with open(input_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = log_pattern.match(line)
            if match:
                ts_str, task_id, target, latency_str = match.groups()
                ts = parse_timestamp(ts_str)
                latency = int(latency_str)

                if task_id not in tasks or ts > tasks[task_id]['ts']:
                    tasks[task_id] = {
                        'ts': ts,
                        'target': target,
                        'latency': latency
                    }

    # Filter for fr-FR
    fr_tasks = [
        (task_id, data['ts'], data['latency']) 
        for task_id, data in tasks.items() 
        if data['target'] == 'fr-FR'
    ]

    # Sort chronologically
    fr_tasks.sort(key=lambda x: x[1])

    expected = []
    latencies = []

    for task_id, ts, latency in fr_tasks:
        latencies.append(latency)
        window = latencies[-3:]
        avg = sum(window) / len(window)
        expected.append({
            'TaskID': task_id,
            'TimestampUTC': ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            'RollingAvgLatency': f"{avg:.2f}"
        })

    return expected

def test_output_file_exists():
    output_path = "/home/user/fr_rolling_stats.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

def test_output_file_content():
    input_path = "/home/user/etl_translation_logs.txt"
    output_path = "/home/user/fr_rolling_stats.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    expected_data = derive_expected_data(input_path)

    actual_data = []
    with open(output_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['TaskID', 'TimestampUTC', 'RollingAvgLatency'], \
            f"CSV headers are incorrect. Expected ['TaskID', 'TimestampUTC', 'RollingAvgLatency'], got {reader.fieldnames}"
        for row in reader:
            actual_data.append(row)

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} rows, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual['TaskID'] == expected['TaskID'], \
            f"Row {i+1}: Expected TaskID {expected['TaskID']}, got {actual['TaskID']}"
        assert actual['TimestampUTC'] == expected['TimestampUTC'], \
            f"Row {i+1}: Expected TimestampUTC {expected['TimestampUTC']}, got {actual['TimestampUTC']}"

        # Compare as floats to allow minor formatting differences like "50.0" vs "50.00" if the student messed up slightly,
        # but the prompt specifically asked for 2 decimal places. We'll enforce string match for exact 2 decimals.
        assert actual['RollingAvgLatency'] == expected['RollingAvgLatency'], \
            f"Row {i+1}: Expected RollingAvgLatency {expected['RollingAvgLatency']}, got {actual['RollingAvgLatency']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
