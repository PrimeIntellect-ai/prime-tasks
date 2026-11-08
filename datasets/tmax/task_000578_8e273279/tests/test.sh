#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_deprecation_report_exists():
    file_path = "/home/user/deprecation_report.csv"
    assert os.path.isfile(file_path), f"The output file was not found at {file_path}"

def test_deprecation_report_content():
    file_path = "/home/user/deprecation_report.csv"
    assert os.path.isfile(file_path), "Cannot check content because the file is missing."

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    header = rows[0]
    assert header == ["DocID", "Author"], f"The CSV header is incorrect. Expected ['DocID', 'Author'], got {header}"

    data_rows = rows[1:]
    expected_rows = [
        ["DOC-2048", "bob@example.com"],
        ["DOC-3015", "diana@example.com"],
        ["DOC-9999", "eve@example.com"]
    ]

    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} is incorrect. Expected {expected}, got {actual}. Ensure rows are sorted by DocID."

def test_deprecation_report_sorting():
    file_path = "/home/user/deprecation_report.csv"
    if not os.path.isfile(file_path):
        pytest.skip("File missing.")

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    if len(rows) <= 1:
        pytest.skip("Not enough data to check sorting.")

    data_rows = rows[1:]
    doc_ids = [row[0] for row in data_rows if len(row) > 0]
    sorted_doc_ids = sorted(doc_ids)

    assert doc_ids == sorted_doc_ids, "The rows in the CSV are not sorted alphabetically by DocID."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
