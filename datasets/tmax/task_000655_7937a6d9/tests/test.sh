#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_output_file_exists():
    """Check if the required output file was generated."""
    assert os.path.isfile("/home/user/cross_institutional_collabs.csv"), "Output file /home/user/cross_institutional_collabs.csv does not exist. Did you run your script?"

def test_output_file_contents():
    """Check if the output file contains the correct results, properly sorted and formatted."""
    expected = [
        ["researcher_1", "researcher_2", "paper_title", "inst_1", "inst_2"],
        ["Bob Jones", "Charlie Brown", "Data Structures in Python", "Global Institute", "Tech University"],
        ["Charlie Brown", "Evan Wright", "Modern Data Science", "Tech University", "Science Center"],
        ["Charlie Brown", "Fiona Gallagher", "Modern Data Science", "Tech University", "Global Institute"],
        ["Diana Prince", "Evan Wright", "AI for Good", "Data Academy", "Science Center"],
        ["Evan Wright", "Fiona Gallagher", "Modern Data Science", "Science Center", "Global Institute"]
    ]

    output_path = "/home/user/cross_institutional_collabs.csv"
    assert os.path.isfile(output_path), "Output file /home/user/cross_institutional_collabs.csv is missing."

    with open(output_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        actual = list(reader)

    assert len(actual) > 0, "The output file is empty."
    assert actual[0] == expected[0], f"Header row is incorrect. Expected {expected[0]}, got {actual[0]}"
    assert len(actual) == len(expected), f"Expected {len(expected)} rows (including header), got {len(actual)} rows."

    for i, (act_row, exp_row) in enumerate(zip(actual, expected)):
        assert act_row == exp_row, f"Row {i} mismatch.\nExpected: {exp_row}\nActual: {act_row}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
