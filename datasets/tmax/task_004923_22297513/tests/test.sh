#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from collections import defaultdict

def test_anomalies_cypher_exists_and_correct():
    csv_path = "/home/user/transactions.csv"
    cypher_path = "/home/user/anomalies.cypher"

    assert os.path.exists(cypher_path), f"File {cypher_path} does not exist."
    assert os.path.isfile(cypher_path), f"Path {cypher_path} is not a file."

    # Recompute expected anomalies
    sender_totals = defaultdict(float)
    sender_counts = defaultdict(int)

    expected_blocks = []

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = row['tx_id']
            sender_id = row['sender_id']
            receiver_id = row['receiver_id']
            amount = float(row['amount'])

            if sender_counts[sender_id] > 0:
                avg = sender_totals[sender_id] / sender_counts[sender_id]
                if amount > 2.0 * avg:
                    block = (
                        f'MERGE (s:User {{id: "{sender_id}"}})\n'
                        f'MERGE (r:User {{id: "{receiver_id}"}})\n'
                        f'CREATE (s)-[:SENT_ANOMALY {{tx_id: "{tx_id}", amount: {amount}}}]->(r);'
                    )
                    expected_blocks.append(block)

            sender_totals[sender_id] += amount
            sender_counts[sender_id] += 1

    expected_cypher = "\n\n".join(expected_blocks) + "\n\n" if expected_blocks else ""

    with open(cypher_path, 'r', encoding='utf-8') as f:
        actual_cypher = f.read()

    # Normalize newlines and trailing spaces for comparison
    actual_normalized = "\n".join([line.rstrip() for line in actual_cypher.splitlines()]).strip()
    expected_normalized = "\n".join([line.rstrip() for line in expected_cypher.splitlines()]).strip()

    assert actual_normalized == expected_normalized, (
        f"Contents of {cypher_path} do not match the expected Cypher script.\n"
        f"Expected:\n{expected_normalized}\n\nActual:\n{actual_normalized}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
