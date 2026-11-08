#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_top_papers_csv_exists():
    """Test that the output CSV file exists."""
    file_path = "/home/user/top_papers.csv"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_top_papers_csv_content():
    """Test that the output CSV has the correct format and data."""
    file_path = "/home/user/top_papers.csv"
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = [row for row in reader if row] # skip empty lines if any

    assert len(rows) == 4, f"Expected 4 rows (1 header + 3 data rows), but found {len(rows)}."

    # Check header
    header = [col.strip() for col in rows[0]]
    assert header == ["uri", "in_degree"], f"Expected header ['uri', 'in_degree'], got {header}."

    # Check data
    expected_data = [
        ["http://example.org/paper1", "5"],
        ["http://example.org/paper3", "2"],
        ["http://example.org/paper4", "2"]
    ]

    for i, expected_row in enumerate(expected_data):
        actual_row = [col.strip() for col in rows[i+1]]
        assert actual_row == expected_row, f"Row {i+1} mismatch: expected {expected_row}, got {actual_row}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
