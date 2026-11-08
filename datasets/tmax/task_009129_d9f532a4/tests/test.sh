#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def get_expected_output(input_csv):
    # Parse the input CSV, handling embedded newlines natively with csv module
    data = []
    with open(input_csv, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'timestamp': int(row['timestamp']),
                'sensor_id': int(row['sensor_id']),
                'value': float(row['value']),
                'message': row['message'].replace('\n', ' ')
            })

    # Group by sensor_id
    sensors = {}
    for row in data:
        sid = row['sensor_id']
        if sid not in sensors:
            sensors[sid] = []
        sensors[sid].append(row)

    processed = []
    for sid, rows in sensors.items():
        rows.sort(key=lambda x: x['timestamp'])
        if not rows:
            continue

        current_time = rows[0]['timestamp']
        end_time = rows[-1]['timestamp']

        idx = 0
        last_val = rows[0]['value']
        window = []

        while current_time <= end_time:
            if idx < len(rows) and current_time == rows[idx]['timestamp']:
                val = rows[idx]['value']
                msg = rows[idx]['message']
                last_val = val
                idx += 1
            else:
                val = last_val
                msg = ""

            window.append(val)
            if len(window) > 3:
                window.pop(0)

            avg = sum(window) / len(window)
            processed.append({
                'timestamp': current_time,
                'sensor_id': sid,
                'value': val,
                'rolling_avg': avg,
                'message': msg
            })
            current_time += 1

    # Sort globally
    processed.sort(key=lambda x: (x['timestamp'], x['sensor_id']))

    # Format to match expected output
    lines = ["timestamp,sensor_id,value,rolling_avg,message"]
    for row in processed:
        lines.append(f"{row['timestamp']},{row['sensor_id']},{row['value']:.2f},{row['rolling_avg']:.2f},\"{row['message']}\"")

    return "\n".join(lines) + "\n"

def test_c_source_exists():
    assert os.path.exists("/home/user/log_processor.c"), "C source file /home/user/log_processor.c is missing."

def test_compiled_binary_exists():
    assert os.path.exists("/home/user/log_processor"), "Compiled binary /home/user/log_processor is missing."
    assert os.access("/home/user/log_processor", os.X_OK), "/home/user/log_processor is not executable."

def test_processed_logs_correctness():
    input_csv = "/home/user/sensor_logs.csv"
    output_csv = "/home/user/processed_logs.csv"

    assert os.path.exists(output_csv), f"Output file {output_csv} is missing."

    expected_csv_content = get_expected_output(input_csv)

    with open(output_csv, 'r', newline='') as f:
        actual_csv_content = f.read()

    actual_lines = [line.strip() for line in actual_csv_content.strip().split('\n')]
    expected_lines = [line.strip() for line in expected_csv_content.strip().split('\n')]

    assert actual_lines == expected_lines, "The processed_logs.csv content does not match the expected output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
