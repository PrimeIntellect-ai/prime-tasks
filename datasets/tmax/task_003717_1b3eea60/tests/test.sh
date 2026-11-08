#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_output_directory_and_file_exist():
    assert os.path.isdir('/home/user/output'), "Output directory /home/user/output/ does not exist."
    assert os.path.isfile('/home/user/output/processed_feedback.csv'), "Output file /home/user/output/processed_feedback.csv does not exist."

def test_processed_feedback_content():
    expected_columns = ["ReviewID", "UserID", "Timestamp", "CleanedText"]

    expected_rows = [
        ["1", "101", "1600000000", "app is great it crashes startup"],
        ["3", "103", "1600000150", "quick brown fox jumps over lazy dog"],
        ["4", "104", "1600000300", "i love it features"],
        ["6", "105", "1600000450", "what fantastic update awesome"],
        ["7", "106", "1600000600", "needs more work ui"],
        ["8", "107", "1600000700", "looking better alternative"],
        ["9", "108", "1600000800", "not bad"],
        ["10", "109", "1600000900", "terrible customer support 5 pm"]
    ]

    file_path = '/home/user/output/processed_feedback.csv'

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, "The output CSV file is completely empty."

        assert header == expected_columns, f"Expected columns {expected_columns}, but got {header}."

        rows = list(reader)

        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}. Check dropping logic (empty/whitespace and duplicates)."

        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."

def test_no_index_column():
    file_path = '/home/user/output/processed_feedback.csv'
    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert "Unnamed: 0" not in header and "" not in header, "Output CSV appears to contain an index column."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
