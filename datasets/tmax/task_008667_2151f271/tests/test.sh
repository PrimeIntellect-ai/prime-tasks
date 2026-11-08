#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import json
import pytest

def get_expected_cycles():
    db_path = '/home/user/data/financial.db'
    jsonl_path = '/home/user/data/transactions.jsonl'

    if not os.path.isfile(db_path) or not os.path.isfile(jsonl_path):
        return []

    # Load users and accounts
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    users = {}
    for row in c.execute('SELECT user_id, name FROM users'):
        users[row[0]] = row[1]

    accounts = {}
    for row in c.execute('SELECT account_id, user_id FROM accounts'):
        accounts[row[0]] = row[1]

    conn.close()

    # Load transactions
    transactions = []
    with open(jsonl_path, 'r') as f:
        for line in f:
            if line.strip():
                tx = json.loads(line)
                from_u = accounts.get(tx['from_account'])
                to_u = accounts.get(tx['to_account'])
                if from_u and to_u:
                    transactions.append({
                        'tx_id': tx['tx_id'],
                        'from_user': from_u,
                        'to_user': to_u,
                        'amount': tx['amount']
                    })

    cycles = {}
    # Find 3-cycles
    for t1 in transactions:
        for t2 in transactions:
            if t1['to_user'] == t2['from_user']:
                for t3 in transactions:
                    if t2['to_user'] == t3['from_user'] and t3['to_user'] == t1['from_user']:
                        u1, u2, u3 = t1['from_user'], t2['from_user'], t3['from_user']
                        if len({u1, u2, u3}) == 3:
                            tx_set = frozenset([t1['tx_id'], t2['tx_id'], t3['tx_id']])
                            if tx_set not in cycles:
                                total_amount = t1['amount'] + t2['amount'] + t3['amount']
                                user_names = sorted([users[u1], users[u2], users[u3]])
                                cycles[tx_set] = {
                                    "users": user_names,
                                    "total_amount": total_amount
                                }

    result = list(cycles.values())
    result.sort(key=lambda x: (-x['total_amount'], x['users'][0]))
    return result

def test_fraud_cycles_output():
    output_path = '/home/user/output/fraud_cycles.json'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON.")

    assert isinstance(output_data, list), "Output JSON must be a list of objects."

    expected_data = get_expected_cycles()

    assert len(output_data) == len(expected_data), f"Expected {len(expected_data)} cycles, found {len(output_data)}."

    for i, (actual, expected) in enumerate(zip(output_data, expected_data)):
        assert "users" in actual, f"Cycle at index {i} missing 'users' key."
        assert "total_amount" in actual, f"Cycle at index {i} missing 'total_amount' key."

        assert isinstance(actual["users"], list), f"'users' at index {i} must be a list."
        assert actual["users"] == expected["users"], f"Expected users {expected['users']} at index {i}, got {actual['users']}. Make sure they are sorted alphabetically."

        assert isinstance(actual["total_amount"], (int, float)), f"'total_amount' at index {i} must be a number."
        assert abs(actual["total_amount"] - expected["total_amount"]) < 1e-6, f"Expected total_amount {expected['total_amount']} at index {i}, got {actual['total_amount']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
