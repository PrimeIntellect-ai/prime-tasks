#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

def get_expected_report(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Read transactions
    cursor.execute("SELECT alpha_id, identifier FROM alpha_records")
    transactions = {row[0]: row[1] for row in cursor.fetchall()}

    # Read held locks
    cursor.execute("SELECT alpha_ref, item_ref FROM beta_records")
    held_locks = {}
    for tx_id, res_id in cursor.fetchall():
        held_locks[res_id] = tx_id  # Assuming exclusive locks

    # Read requested locks
    cursor.execute("SELECT alpha_ref, item_ref FROM gamma_records")
    requested_locks = cursor.fetchall()

    conn.close()

    # Build wait-for graph
    # edge from X to Y means X waits for Y
    graph = {tx: [] for tx in transactions}
    in_degree = {tx: 0 for tx in transactions} # blocking score: how many wait on tx

    for req_tx, res_id in requested_locks:
        if res_id in held_locks:
            holder_tx = held_locks[res_id]
            if req_tx != holder_tx:
                graph[req_tx].append(holder_tx)
                in_degree[holder_tx] += 1

    # Find deadlocks (nodes in cycles)
    def find_cycles():
        visited = set()
        rec_stack = set()
        in_cycle = set()

        def dfs(node, path):
            visited.add(node)
            rec_stack.add(node)
            path.append(node)

            for neighbor in graph[node]:
                if neighbor not in visited:
                    dfs(neighbor, path)
                elif neighbor in rec_stack:
                    # Cycle detected
                    cycle_start_idx = path.index(neighbor)
                    for n in path[cycle_start_idx:]:
                        in_cycle.add(n)

            rec_stack.remove(node)
            path.pop()

        for node in graph:
            if node not in visited:
                dfs(node, [])

        return in_cycle

    deadlocked_nodes = find_cycles()

    results = []
    for node in deadlocked_nodes:
        results.append({
            "transaction_name": transactions[node],
            "blocking_score": in_degree[node]
        })

    # Sort DESC by blocking_score, ASC by transaction_name
    results.sort(key=lambda x: (-x["blocking_score"], x["transaction_name"]))

    return results[:3]

def test_deadlock_report():
    report_path = "/home/user/deadlock_report.json"
    db_path = "/home/user/db_locks.sqlite"

    assert os.path.exists(db_path), f"Database file {db_path} is missing."
    assert os.path.exists(report_path), f"Output file {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            student_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    expected_report = get_expected_report(db_path)

    assert isinstance(student_report, list), f"Expected JSON root to be a list, got {type(student_report).__name__}."
    assert len(student_report) == len(expected_report), f"Expected {len(expected_report)} items in report, got {len(student_report)}."

    for i, (expected, student) in enumerate(zip(expected_report, student_report)):
        assert isinstance(student, dict), f"Item at index {i} should be a dictionary."

        assert "transaction_name" in student, f"Item at index {i} missing 'transaction_name' key."
        assert student["transaction_name"] == expected["transaction_name"], \
            f"Expected transaction_name '{expected['transaction_name']}' at index {i}, got '{student['transaction_name']}'."

        assert "blocking_score" in student, f"Item at index {i} missing 'blocking_score' key."
        assert student["blocking_score"] == expected["blocking_score"], \
            f"Expected blocking_score {expected['blocking_score']} at index {i}, got {student['blocking_score']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
