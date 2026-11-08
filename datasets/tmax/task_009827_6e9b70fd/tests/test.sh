#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_rolling_es_output():
    input_file = "/home/user/translation_logs.csv"
    output_file = "/home/user/rolling_es.txt"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    valid_counts = []
    with open(input_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("lang") == "es-ES":
                try:
                    chars = int(row.get("chars_translated", 0))
                    if 1 <= chars <= 5000:
                        valid_counts.append(chars)
                except ValueError:
                    pass

    expected_averages = []
    for i in range(len(valid_counts) - 2):
        window = valid_counts[i:i+3]
        avg = sum(window) / 3.0
        expected_averages.append(f"{avg:.1f}")

    with open(output_file, "r") as f:
        actual_output = [line.strip() for line in f if line.strip()]

    assert actual_output == expected_averages, (
        f"Expected output {expected_averages}, but got {actual_output}. "
        "Make sure to filter correctly and calculate a 3-event rolling average formatted to 1 decimal place."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
