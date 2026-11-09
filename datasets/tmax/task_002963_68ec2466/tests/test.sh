#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_flagged_cycles_file_exists():
    """Test that the output file flagged_cycles.csv exists."""
    file_path = '/home/user/flagged_cycles.csv'
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

def test_flagged_cycles_content():
    """Test that the output file contains the correct flagged cycles and max 7-day sums."""
    file_path = '/home/user/flagged_cycles.csv'

    expected_rows = [
        ['A', 'B', 'C', '12000'],
        ['X', 'Y', 'Z', '10500']
    ]

    actual_rows = []
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # Ignore empty lines
                actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."

def test_flagged_cycles_sorting():
    """Test that the accounts in each row are sorted alphabetically, and rows are sorted by the first account."""
    file_path = '/home/user/flagged_cycles.csv'

    actual_rows = []
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_rows.append(row)

    # Check that each row's accounts are sorted
    for i, row in enumerate(actual_rows):
        accounts = row[:3]
        assert accounts == sorted(accounts), f"Accounts in row {i+1} are not sorted alphabetically: {accounts}"

    # Check that rows are sorted by the first account
    first_accounts = [row[0] for row in actual_rows]
    assert first_accounts == sorted(first_accounts), f"Rows are not sorted alphabetically by the first account: {first_accounts}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
