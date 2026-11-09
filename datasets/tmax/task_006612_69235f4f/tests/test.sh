#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import csv
import pytest

def get_expected_audit():
    # 1. Detect Deadlocks
    wait_graph_path = "/home/user/wait_graph.csv"
    edges = set()
    with open(wait_graph_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 2:
                edges.add((int(row[0]), int(row[1])))

    deadlocked_txs = set()
    for waiter, holder in edges:
        if (holder, waiter) in edges:
            deadlocked_txs.add(waiter)
            deadlocked_txs.add(holder)

    # 2. Analyze Relative Priority
    db_path = "/home/user/tx_history.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    SELECT tx_id, user_id, amount_rank
    FROM (
        SELECT tx_id, user_id, 
               RANK() OVER (PARTITION BY user_id ORDER BY amount DESC) as amount_rank
        FROM transactions
    )
    """
    cursor.execute(query)
    ranks = {}
    for row in cursor.fetchall():
        tx_id, user_id, amount_rank = row
        if tx_id in deadlocked_txs:
            ranks[tx_id] = {"user_id": user_id, "amount_rank": amount_rank}
    conn.close()

    # 3. Extract Held Resources
    jsonl_path = "/home/user/lock_events.jsonl"
    resources = {tx_id: set() for tx_id in deadlocked_txs}
    with open(jsonl_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            event_data = json.loads(line)
            tx_id = event_data.get("tx_id")
            if tx_id in deadlocked_txs and event_data.get("event") == "acquire":
                resources[tx_id].add(event_data.get("resource"))

    # 4. Compile and Export
    expected_output = []
    for tx_id in sorted(deadlocked_txs):
        expected_output.append({
            "tx_id": tx_id,
            "user_id": ranks[tx_id]["user_id"],
            "amount_rank": ranks[tx_id]["amount_rank"],
            "resources_held": sorted(list(resources[tx_id]))
        })

    return expected_output

def test_deadlock_audit_json_exists():
    assert os.path.exists("/home/user/deadlock_audit.json"), "The file /home/user/deadlock_audit.json is missing."

def test_deadlock_audit_json_content():
    expected = get_expected_audit()

    with open("/home/user/deadlock_audit.json", "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/deadlock_audit.json does not contain valid JSON.")

    assert isinstance(actual, list), "The JSON output must be a list of objects."

    assert len(actual) == len(expected), f"Expected {len(expected)} deadlocked transactions, but found {len(actual)}."

    for act, exp in zip(actual, expected):
        assert act.get("tx_id") == exp["tx_id"], f"Expected tx_id {exp['tx_id']}, got {act.get('tx_id')}."
        assert act.get("user_id") == exp["user_id"], f"Expected user_id {exp['user_id']} for tx_id {exp['tx_id']}, got {act.get('user_id')}."
        assert act.get("amount_rank") == exp["amount_rank"], f"Expected amount_rank {exp['amount_rank']} for tx_id {exp['tx_id']}, got {act.get('amount_rank')}."

        act_resources = act.get("resources_held", [])
        assert isinstance(act_resources, list), f"resources_held for tx_id {exp['tx_id']} must be a list."
        assert act_resources == exp["resources_held"], f"Expected resources_held {exp['resources_held']} for tx_id {exp['tx_id']}, got {act_resources}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
