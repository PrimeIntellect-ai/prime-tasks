#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

OUTPUT_FILE = "/home/user/output/rolling_configs.csv"

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

def test_csv_header():
    with open(OUTPUT_FILE, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        expected_header = ['timestamp', 'app_id', 'memory_limit_mb', 'rolling_avg_memory']
        assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}."

def test_csv_content():
    expected_rows = [
        ['1620000010', 'app1', '100', '100.00'],
        ['1620000020', 'app2', '300', '200.00'],
        ['1620000030', 'app1', '200', '200.00'],
        ['1620000040', 'app2', '400', '300.00'],
        ['1620000050', 'app1', '150', '250.00'],
        ['1620000060', 'app2', '250', '266.67'],
        ['1620000070', 'app1', '500', '300.00'],
        ['1620000080', 'app2', '350', '366.67']
    ]

    with open(OUTPUT_FILE, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            next(reader) # skip header
        except StopIteration:
            pytest.fail("CSV file contains no data rows.")

        rows = list(reader)

        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."

        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."

def test_rolling_avg_logic():
    # Verify the rolling average computation independently
    with open(OUTPUT_FILE, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

        memory_limits = []
        for i, row in enumerate(rows):
            try:
                mem = int(row['memory_limit_mb'])
            except ValueError:
                pytest.fail(f"Invalid memory_limit_mb at row {i+1}: {row['memory_limit_mb']}")

            memory_limits.append(mem)

            # calculate expected rolling avg
            window = memory_limits[max(0, i-2):i+1]
            expected_avg = sum(window) / len(window)
            expected_avg_str = f"{expected_avg:.2f}"

            actual_avg_str = row['rolling_avg_memory']
            assert actual_avg_str == expected_avg_str, f"Rolling average mismatch at row {i+1}. Expected {expected_avg_str}, got {actual_avg_str}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
