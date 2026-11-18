#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

CSV_PATH = "/home/user/genomics_datasets.csv"

def test_csv_file_exists():
    """Check if the output CSV file was created at the correct location."""
    assert os.path.isfile(CSV_PATH), f"Output file not found at {CSV_PATH}. Make sure you exported the results to the correct path."

def test_csv_contents():
    """Check if the CSV contains the correct headers and data, properly sorted."""
    expected_rows = [
        ["title", "author"],
        ["Human Genome v38", "Alice Smith"],
        ["Human Genome v38", "Bob Jones"],
        ["Mouse RNA-Seq Timecourse", "Charlie Brown"],
        ["PBMC 10k Cells", "Diana Prince"]
    ]

    actual_rows = []
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) > 0, "The CSV file is empty."

    # Check headers
    assert actual_rows[0] == expected_rows[0], f"CSV headers are incorrect. Expected {expected_rows[0]}, but got {actual_rows[0]}."

    # Check data and sorting
    assert len(actual_rows) == len(expected_rows), f"CSV has incorrect number of rows. Expected {len(expected_rows)}, but got {len(actual_rows)}."

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Row {i} is incorrect or not properly sorted. Expected {expected_rows[i]}, but got {actual_rows[i]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
