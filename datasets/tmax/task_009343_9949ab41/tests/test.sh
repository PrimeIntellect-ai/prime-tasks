#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_rolling_stats_output():
    input_file = "/home/user/config_changes.csv"
    output_file = "/home/user/rolling_stats.csv"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    # Compute expected output based on the logic described in the task
    expected_rows = [["timestamp", "service_name", "payload_length", "rolling_avg_length"]]

    last_payloads = {}
    length_windows = {}

    with open(input_file, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        # Sort chronologically to ensure correct processing order
        rows.sort(key=lambda x: x["timestamp"])

        for row in rows:
            ts = row["timestamp"]
            svc = row["service_name"]
            payload = row["config_payload"]

            # Deduplicate no-op changes
            if last_payloads.get(svc) == payload:
                continue

            last_payloads[svc] = payload
            length = len(payload)

            if svc not in length_windows:
                length_windows[svc] = []
            length_windows[svc].append(length)

            # Calculate rolling average over a window of the last 3 retained changes
            window = length_windows[svc][-3:]
            avg = sum(window) / len(window)

            expected_rows.append([ts, svc, str(length), f"{avg:.2f}"])

    # Read actual output
    with open(output_file, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "Output file is empty."
    assert actual_rows[0] == expected_rows[0], "Incorrect headers in output file."

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
