#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_anomalies_file_exists():
    assert os.path.isfile("/home/user/anomalies.csv"), "The output file /home/user/anomalies.csv does not exist."

def test_anomalies_content():
    input_file = "/home/user/api_latency.csv"
    output_file = "/home/user/anomalies.csv"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    # Compute expected anomalies
    expected_anomalies = []
    window = []

    with open(input_file, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 3:
                continue

            timestamp, endpoint, latency_str = row[0], row[1], row[2]
            latency = float(latency_str)

            if len(window) == 5:
                rolling_avg = sum(window) / 5.0
                if latency > 2.0 * rolling_avg:
                    expected_anomalies.append(f"{timestamp},{endpoint},{int(latency)},{rolling_avg:.1f}")

                window.pop(0)

            window.append(latency)

    # Read actual anomalies
    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    # Compare
    assert len(actual_lines) == len(expected_anomalies), (
        f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_anomalies)):
        assert actual == expected, (
            f"Mismatch at line {i+1} of anomalies.csv.\n"
            f"Expected: {expected}\n"
            f"Found:    {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
