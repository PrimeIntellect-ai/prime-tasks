#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_restore_costs_csv_exists():
    """Test that the restore_costs.csv file was created."""
    file_path = "/home/user/restore_costs.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you write the output to the correct path?"

def test_restore_costs_csv_content():
    """Test that the restore_costs.csv file contains the correct calculated data and ranking."""
    file_path = "/home/user/restore_costs.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    expected_rows = [
        ["backup_id", "total_restore_size_mb", "cost_rank"],
        ["b09", "2450", "1"],
        ["b04", "2400", "2"],
        ["b08", "2400", "2"],
        ["b03", "2350", "3"],
        ["b07", "2200", "4"],
        ["b02", "2150", "5"],
        ["b01", "2000", "6"],
        ["b06", "1800", "7"],
        ["b05", "1500", "8"]
    ]

    actual_rows = []
    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            # Strip whitespace just in case
            actual_rows.append([col.strip() for col in row])

    assert len(actual_rows) > 0, f"File {file_path} is empty."

    # Check header
    assert actual_rows[0] == expected_rows[0], f"Header row is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}"

    # Check data
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)} rows."

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Row {i+1} is incorrect. Expected {expected_rows[i]}, got {actual_rows[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
