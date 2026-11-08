#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
from datetime import datetime, timedelta

def process_logs_reference(raw_logs_path):
    with open(raw_logs_path, 'r', encoding='latin1') as f:
        lines = f.readlines()

    seen = set()
    valid_logs = []

    for line in lines:
        line = line.strip('\n')
        if not line:
            continue

        parts = line.split(" | ", 2)
        if len(parts) != 3:
            continue

        timestamp_str, user_id, message = parts

        # Clean message
        cleaned_message = "".join(c for c in message if 32 <= ord(c) <= 126)

        # Deduplicate
        dedup_key = (user_id, cleaned_message)
        if dedup_key in seen:
            continue
        seen.add(dedup_key)

        try:
            dt = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue

        valid_logs.append((dt, user_id, cleaned_message))

    # Group by minute
    start_time = datetime(2023, 10, 1, 10, 0, 0)
    end_time = datetime(2023, 10, 1, 10, 15, 0)

    minute_bins = {}
    current_time = start_time
    while current_time <= end_time:
        minute_bins[current_time] = []
        current_time += timedelta(minutes=1)

    for dt, user_id, msg in valid_logs:
        bin_time = dt.replace(second=0, microsecond=0)
        if start_time <= bin_time <= end_time:
            minute_bins[bin_time].append((dt, user_id, msg))

    expected_lines = []
    current_time = start_time
    while current_time <= end_time:
        entries = minute_bins[current_time]
        if entries:
            # Sort by actual timestamp to get the earliest
            entries.sort(key=lambda x: x[0])
            _, user_id, msg = entries[0]
            expected_lines.append(f"{current_time.strftime('%Y-%m-%d %H:%M:%S')} | {user_id} | {msg}")
        else:
            expected_lines.append(f"{current_time.strftime('%Y-%m-%d %H:%M:%S')} | SYSTEM | NO_ACTIVITY")

        current_time += timedelta(minutes=1)

    return expected_lines

def test_processed_logs_correctness():
    processed_logs_path = "/home/user/processed_logs.txt"
    raw_logs_path = "/home/user/raw_logs.txt"

    assert os.path.exists(processed_logs_path), f"The output file {processed_logs_path} does not exist."
    assert os.path.isfile(processed_logs_path), f"The path {processed_logs_path} is not a file."

    expected_lines = process_logs_reference(raw_logs_path)

    with open(processed_logs_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip('\n') for line in f.readlines() if line.strip('\n')]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)} lines in {processed_logs_path}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}:\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
