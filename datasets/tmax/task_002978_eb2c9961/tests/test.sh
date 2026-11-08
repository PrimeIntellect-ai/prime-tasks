#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_csv_exists():
    csv_path = '/home/user/circular_flows.csv'
    assert os.path.isfile(csv_path), f"Output CSV file {csv_path} does not exist."

def test_csv_content():
    csv_path = '/home/user/circular_flows.csv'
    assert os.path.isfile(csv_path), f"Output CSV file {csv_path} does not exist."

    expected_headers = ['acct_A', 'acct_B', 'acct_C', 'cycle_total', 'risk_rank']
    expected_rows = {
        ('Xavier', 'Yolanda', 'Zack'): (15000.0, '1'),
        ('Alice', 'Bob', 'Charlie'): (4500.0, '2')
    }

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

        rows = list(reader)
        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(rows)}."

        for i, actual in enumerate(rows):
            assert len(actual) == 5, f"Row {i+1} has {len(actual)} columns, expected 5."

        actual_accounts = [tuple(row[:3]) for row in rows]
        assert len(set(actual_accounts)) == len(actual_accounts), "CSV contains duplicate cycle rows."
        assert set(actual_accounts) == set(expected_rows), \
            f"Cycle accounts mismatch: expected {set(expected_rows)}, got {set(actual_accounts)}"

        for i, actual in enumerate(rows):
            accounts = tuple(actual[:3])
            expected_total, expected_rank = expected_rows[accounts]

            # Check cycle_total (allow for float representation differences)
            try:
                actual_total = float(actual[3])
            except ValueError:
                pytest.fail(f"Row {i+1} cycle_total '{actual[3]}' is not a valid float.")
            assert actual_total == expected_total, \
                f"Row {i+1} cycle_total mismatch: expected {expected_total}, got {actual_total}"

            # Check risk_rank
            assert actual[4] == expected_rank, \
                f"Row {i+1} risk_rank mismatch: expected '{expected_rank}', got '{actual[4]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
