#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import os
import pytest
from collections import defaultdict

def test_final_report_exists():
    """Check if the final report file was generated."""
    assert os.path.exists("/home/user/final_report.csv"), "/home/user/final_report.csv does not exist."

def test_final_report_content():
    """Verify the data processing logic (dedup, join, sort, cumsum, top 2)."""
    # 1. Read users data
    users = {}
    users_path = '/home/user/data/users.csv'
    assert os.path.exists(users_path), f"{users_path} is missing."
    with open(users_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[row['user_id']] = row['region']

    # 2. Read and deduplicate transactions from both batches
    txs = {}
    for batch_file in ['/home/user/data/tx_batch1.csv', '/home/user/data/tx_batch2.csv']:
        assert os.path.exists(batch_file), f"{batch_file} is missing."
        with open(batch_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Deduplication by transaction_id
                txs[row['transaction_id']] = row

    # Group by user_id
    user_txs = defaultdict(list)
    for tx in txs.values():
        user_txs[tx['user_id']].append(tx)

    # 3-5. Sort, calculate cumulative sum, and retain first 2 transactions
    expected_rows = []
    for user_id in sorted(user_txs.keys()):
        # Sort chronologically
        user_txs[user_id].sort(key=lambda x: x['timestamp'])

        cum_sum = 0.0
        # Retain only the first 2 transactions
        for tx in user_txs[user_id][:2]:
            amt = float(tx['amount'])
            cum_sum += amt
            expected_rows.append({
                'transaction_id': tx['transaction_id'],
                'user_id': user_id,
                'region': users.get(user_id, ''),
                'timestamp': tx['timestamp'],
                'amount': f"{amt:.1f}",
                'cumulative_amount': f"{cum_sum:.1f}"
            })

    # 6. Read actual final report and compare
    actual_rows = []
    with open('/home/user/final_report.csv', 'r') as f:
        reader = csv.DictReader(f)

        # Verify header exactly
        expected_header = ['transaction_id', 'user_id', 'region', 'timestamp', 'amount', 'cumulative_amount']
        assert reader.fieldnames == expected_header, f"Header mismatch. Expected {expected_header}, got {reader.fieldnames}"

        for row in reader:
            # Format amounts to 1 decimal place to handle trailing zeros gracefully if parsed as float
            try:
                row['amount'] = f"{float(row['amount']):.1f}"
                row['cumulative_amount'] = f"{float(row['cumulative_amount']):.1f}"
            except ValueError:
                pass # Let the assertion fail below if amounts are not numeric
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in the final report, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} (after header) mismatch.\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
