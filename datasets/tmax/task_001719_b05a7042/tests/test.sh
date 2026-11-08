#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

OUTPUT_FILE = "/home/user/department_costs.csv"

def test_output_file_exists():
    """Test that the output file was created."""
    assert os.path.isfile(OUTPUT_FILE), f"The file {OUTPUT_FILE} does not exist."

def test_no_quotes_in_file():
    """Test that the output file does not contain quotes."""
    with open(OUTPUT_FILE, "r") as f:
        content = f.read()
    assert '"' not in content and "'" not in content, "The output file should not contain quotes."

def test_output_file_content_and_format():
    """Test the header, row count, sorting, and values of the output CSV."""
    with open(OUTPUT_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The output file is empty."

    header = rows[0]
    assert header == ["root_dept_name", "total_cost"], f"Incorrect header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows, found {len(data_rows)}"

    # Parse data
    parsed_data = []
    for row in data_rows:
        assert len(row) == 2, f"Row does not have exactly 2 columns: {row}"
        dept_name = row[0].strip()
        try:
            total_cost = float(row[1].strip())
        except ValueError:
            pytest.fail(f"Total cost '{row[1]}' is not a valid number.")
        parsed_data.append((dept_name, total_cost))

    # Check descending order
    costs = [cost for _, cost in parsed_data]
    assert costs == sorted(costs, reverse=True), "Rows are not sorted by total_cost in descending order."

    # Check exact values
    expected_data = {
        "Engineering": 3500.0,
        "Sales": 2550.0,
        "HR": 1540.0
    }

    actual_data = {dept: cost for dept, cost in parsed_data}

    for dept, expected_cost in expected_data.items():
        assert dept in actual_data, f"Root department '{dept}' is missing from the output."
        assert actual_data[dept] == expected_cost, f"Incorrect total_cost for '{dept}'. Expected {expected_cost}, got {actual_data[dept]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
