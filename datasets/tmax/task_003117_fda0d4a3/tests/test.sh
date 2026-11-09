#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest
from collections import defaultdict

INPUT_CSV = '/home/user/transactions.csv'
OUTPUT_CSV = '/home/user/processed_transactions.csv'

def get_expected_data():
    if not os.path.exists(INPUT_CSV):
        pytest.fail(f"Input file {INPUT_CSV} is missing.")

    with open(INPUT_CSV, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    valid_rows = []
    for row in rows:
        try:
            amount = float(row['amount'])
        except ValueError:
            continue

        if amount < 0:
            continue

        date = row['date']
        if date > '2023-12-31':
            continue

        ssn = row['ssn']
        if len(ssn) != 9 or not ssn.isdigit():
            continue

        valid_rows.append({
            'transaction_id': row['transaction_id'],
            'user_id': row['user_id'],
            'ssn': ssn,
            'date': date,
            'amount': amount
        })

    # Sort by user_id, date, transaction_id
    valid_rows.sort(key=lambda x: (x['user_id'], x['date'], x['transaction_id']))

    # Group by user_id to calculate rolling average
    user_groups = defaultdict(list)
    for row in valid_rows:
        user_groups[row['user_id']].append(row)

    expected_output = []
    for user_id in sorted(user_groups.keys()):
        group = user_groups[user_id]
        window = []
        for row in group:
            window.append(row['amount'])
            if len(window) > 3:
                window.pop(0)

            rolling_avg = sum(window) / len(window)

            expected_output.append({
                'transaction_id': row['transaction_id'],
                'user_id': row['user_id'],
                'ssn_masked': 'XXXXX' + row['ssn'][5:],
                'date': row['date'],
                'amount': f"{row['amount']:.1f}" if row['amount'].is_integer() else str(row['amount']),
                'rolling_avg_amount': f"{rolling_avg:.2f}"
            })

    return expected_output

def test_output_file_exists():
    """Ensure the processed file exists."""
    assert os.path.isfile(OUTPUT_CSV), f"The output file '{OUTPUT_CSV}' was not created."

def test_output_file_content():
    """Validate the content of the processed CSV against the expected logic."""
    if not os.path.isfile(OUTPUT_CSV):
        pytest.fail(f"Cannot check content because '{OUTPUT_CSV}' is missing.")

    expected_data = get_expected_data()

    with open(OUTPUT_CSV, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The file '{OUTPUT_CSV}' is empty.")

        expected_header = ['transaction_id', 'user_id', 'ssn_masked', 'date', 'amount', 'rolling_avg_amount']
        assert header == expected_header, f"Expected header {expected_header}, but got {header}."

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_data)):
        assert actual[0] == expected['transaction_id'], f"Row {i+1}: Expected transaction_id '{expected['transaction_id']}', got '{actual[0]}'"
        assert actual[1] == expected['user_id'], f"Row {i+1}: Expected user_id '{expected['user_id']}', got '{actual[1]}'"
        assert actual[2] == expected['ssn_masked'], f"Row {i+1}: Expected ssn_masked '{expected['ssn_masked']}', got '{actual[2]}'"
        assert actual[3] == expected['date'], f"Row {i+1}: Expected date '{expected['date']}', got '{actual[3]}'"

        actual_amount = float(actual[4])
        expected_amount = float(expected['amount'])
        assert actual_amount == expected_amount, f"Row {i+1}: Expected amount {expected_amount}, got {actual_amount}"

        actual_rolling = float(actual[5])
        expected_rolling = float(expected['rolling_avg_amount'])
        assert actual_rolling == expected_rolling, f"Row {i+1}: Expected rolling_avg_amount {expected_rolling}, got {actual_rolling}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
