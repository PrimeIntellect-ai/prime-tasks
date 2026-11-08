#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_processed_equations_csv_exists():
    file_path = "/home/user/processed_equations.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_processed_equations_csv_content():
    file_path = "/home/user/processed_equations.csv"
    assert os.path.exists(file_path), "CSV file not found"

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty"

    header = rows[0]
    assert header == ['Equation', 'Value'], f"Incorrect columns. Expected ['Equation', 'Value'], got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 6, f"Expected 6 rows of data, got {len(data_rows)}"

    expected_data = [
        ["10*(2+3)", "50.00"],
        ["10/4", "2.50"],
        ["100-50", "50.00"],
        ["15+25", "40.00"],
        ["20-2", "18.00"],
        ["3*3", "9.00"]
    ]

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(actual) == 2, f"Row {i+1} does not have exactly 2 columns"

        actual_eq, actual_val = actual
        expected_eq, expected_val = expected

        assert actual_eq == expected_eq, f"Equation mismatch at row {i+1}. Expected {expected_eq}, got {actual_eq}"

        # Check value format. It should be exact string match or a float that matches
        try:
            val_float = float(actual_val)
            formatted_val = format(val_float, ".2f")
            assert formatted_val == expected_val, f"Value mismatch at row {i+1}. Expected {expected_val}, got {actual_val}"
        except ValueError:
            pytest.fail(f"Value at row {i+1} is not a valid number: {actual_val}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
