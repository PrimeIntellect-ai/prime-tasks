#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_diagnostic_report_exists_and_correct():
    csv_path = '/home/user/measurements.csv'
    report_path = '/home/user/diagnostic_report.txt'

    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
    assert os.path.isfile(report_path), f"Diagnostic report {report_path} was not created."

    # Determine the correct row dynamically
    expected_row_index = None
    with open(csv_path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 1, "CSV file is empty or missing data rows."

    for i, line in enumerate(lines[1:]): # 0-indexed data row
        parts = line.split(',')
        if len(parts) == 2:
            val_str = parts[1].strip()
            # Check if it parses to 0.0 but is mathematically non-zero
            # A simple heuristic: it parses to 0.0, but doesn't consist of just '0', '0.0', '-0.0', etc.
            try:
                val_float = float(val_str)
                if val_float == 0.0:
                    # check if the string itself has non-zero digits
                    if any(c in '123456789' for c in val_str):
                        expected_row_index = i
                        break
            except ValueError:
                pass

    assert expected_row_index is not None, "Could not find the underflow row in the CSV."

    with open(report_path, 'r') as f:
        report_content = f.read().strip()

    expected_content = f"Corrupted Row: {expected_row_index}"

    assert report_content == expected_content, (
        f"Diagnostic report content is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Found: '{report_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
