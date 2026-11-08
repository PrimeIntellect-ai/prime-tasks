#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

DB_PATH = "/home/user/transactions.db"
REPORT_PATH = "/home/user/deadlock_report.json"

def compute_expected_results():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Get active transactions
    cursor.execute("SELECT tx_id FROM transactions WHERE status = 'ACTIVE'")
    active_txs = set(row[0] for row in cursor.fetchall())

    # Get all waits-for edges among active transactions
    query = """
        SELECT w.tx_id AS waiter, h.tx_id AS holder
        FROM locks_waiting w
        JOIN locks_held h ON w.resource_id = h.resource_id
        JOIN transactions tw ON w.tx_id = tw.tx_id
        JOIN transactions th ON h.tx_id = th.tx_id
        WHERE tw.status = 'ACTIVE' AND th.status = 'ACTIVE'
    """
    cursor.execute(query)
    edges = cursor.fetchall()
    conn.close()

    # Build adjacency lists
    adj = {tx: [] for tx in active_txs}
    in_degree = {tx: 0 for tx in active_txs}

    for u, v in edges:
        if u in active_txs and v in active_txs:
            adj[u].append(v)
            in_degree[v] += 1

    # Find SCCs using Tarjan's or Kosaraju's, but since we can just use a simple DFS for small graphs:
    # Actually, let's implement Tarjan's bridge-finding / SCC algorithm
    index = 0
    indices = {}
    lowlinks = {}
    on_stack = set()
    stack = []
    sccs = []

    def strongconnect(v):
        nonlocal index
        indices[v] = index
        lowlinks[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)

        for w in adj[v]:
            if w not in indices:
                strongconnect(w)
                lowlinks[v] = min(lowlinks[v], lowlinks[w])
            elif w in on_stack:
                lowlinks[v] = min(lowlinks[v], indices[w])

        if lowlinks[v] == indices[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == v:
                    break
            sccs.append(scc)

    for v in active_txs:
        if v not in indices:
            strongconnect(v)

    # Filter for deadlocks (SCC > 1 node)
    deadlocks = [sorted(scc) for scc in sccs if len(scc) > 1]
    deadlocks.sort(key=lambda x: x[0])

    deadlocked_txs = set()
    for scc in deadlocks:
        deadlocked_txs.update(scc)
    deadlocked_txs_sorted = sorted(list(deadlocked_txs))

    # Most blocking tx in the deadlocked set? 
    # The prompt says: "Among all the transactions that are involved in *any* deadlock, identify the `most_blocking_tx`. This is the transaction with the highest in-degree (number of incoming wait-for edges) in the *entire* active graph. If there is a tie, pick the one with the smallest `tx_id`."
    most_blocking_tx = None
    max_in_degree = -1
    for tx in deadlocked_txs_sorted:
        deg = in_degree[tx]
        if deg > max_in_degree:
            max_in_degree = deg
            most_blocking_tx = tx
        elif deg == max_in_degree:
            most_blocking_tx = min(most_blocking_tx, tx)

    # Edges between deadlocked nodes
    deadlock_edges = []
    for u, v in edges:
        if u in deadlocked_txs and v in deadlocked_txs:
            deadlock_edges.append((u, v))

    deadlock_edges.sort(key=lambda e: (e[0], e[1]))

    paginated_edges = {}
    page_num = 1
    for i in range(0, len(deadlock_edges), 2):
        chunk = deadlock_edges[i:i+2]
        paginated_edges[f"page_{page_num}"] = [{"waiter": u, "holder": v} for u, v in chunk]
        page_num += 1

    return {
        "deadlocked_transactions": deadlocked_txs_sorted,
        "clusters": deadlocks,
        "most_blocking_tx": most_blocking_tx,
        "paginated_edges": paginated_edges
    }

def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

def test_report_schema_and_values():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report file is not valid JSON.")

    expected = compute_expected_results()

    assert "deadlocked_transactions" in report, "Missing 'deadlocked_transactions' key."
    assert report["deadlocked_transactions"] == expected["deadlocked_transactions"], \
        f"Expected deadlocked_transactions: {expected['deadlocked_transactions']}, got: {report.get('deadlocked_transactions')}"

    assert "clusters" in report, "Missing 'clusters' key."
    assert report["clusters"] == expected["clusters"], \
        f"Expected clusters: {expected['clusters']}, got: {report.get('clusters')}"

    assert "most_blocking_tx" in report, "Missing 'most_blocking_tx' key."
    assert report["most_blocking_tx"] == expected["most_blocking_tx"], \
        f"Expected most_blocking_tx: {expected['most_blocking_tx']}, got: {report.get('most_blocking_tx')}"

    assert "paginated_edges" in report, "Missing 'paginated_edges' key."
    assert report["paginated_edges"] == expected["paginated_edges"], \
        f"Expected paginated_edges: {expected['paginated_edges']}, got: {report.get('paginated_edges')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
