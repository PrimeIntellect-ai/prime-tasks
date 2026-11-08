#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import pytest
from collections import deque

REPORT_PATH = '/home/user/audit_report.json'
DB_PATH = '/home/user/financial_audit.db'

EXPECTED_ACCOUNTS = [
    ('A1', 'domestic', 10),
    ('A2', 'domestic', 90),
    ('A3', 'domestic', 20),
    ('A4', 'domestic', 50),
    ('A5', 'offshore', 30),
    ('A6', 'domestic', 85),
    ('A7', 'offshore', 40),
    ('A8', 'domestic', 15),
]

EXPECTED_TRANSACTIONS = [
    ('T1', 'A2', 'A1', 100.0),
    ('T2', 'A1', 'A3', 200.0),
    ('T3', 'A3', 'A5', 300.0),
    ('T4', 'A6', 'A4', 400.0),
    ('T5', 'A4', 'A1', 500.0),
    ('T6', 'A4', 'A7', 600.0),
    ('T7', 'A5', 'A2', 700.0),
    ('T8', 'A8', 'A6', 800.0),
    ('T9', 'A1', 'A8', 900.0),
]

def get_db_data():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT account_id, account_type, risk_score FROM accounts")
    accounts = c.fetchall()

    c.execute("SELECT source_account, target_account FROM transactions")
    edges = c.fetchall()

    conn.close()
    return accounts, edges

def compute_pagerank(nodes, edges, d=0.85, tol=1e-6, max_iter=100):
    N = len(nodes)
    if N == 0:
        return {}

    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    pr = {n: 1.0 / N for n in nodes}

    for _ in range(max_iter):
        prev_pr = pr.copy()
        dangling_mass = sum(prev_pr[n] for n in nodes if out_degree[n] == 0)

        for n in nodes:
            pr[n] = (1 - d) / N + d * dangling_mass / N

        for u, v in edges:
            pr[v] += d * prev_pr[u] / out_degree[u]

        err = sum(abs(pr[n] - prev_pr[n]) for n in nodes)
        if err < N * tol:
            break

    return pr

def find_shortest_path(nodes, edges, high_risk, offshore):
    adj = {n: [] for n in nodes}
    for u, v in edges:
        adj[u].append(v)

    best_paths = []
    min_length = float('inf')

    for start in sorted(high_risk):
        queue = deque([[start]])
        visited = {start: 1}

        while queue:
            path = queue.popleft()
            curr = path[-1]

            if len(path) > min_length:
                continue

            if curr in offshore:
                if len(path) < min_length:
                    min_length = len(path)
                    best_paths = [path]
                elif len(path) == min_length:
                    best_paths.append(path)
                continue

            for neighbor in adj[curr]:
                if neighbor not in visited or visited[neighbor] >= len(path) + 1:
                    visited[neighbor] = len(path) + 1
                    queue.append(path + [neighbor])

    if not best_paths:
        return []

    best_paths.sort(key=lambda p: p[0])
    return best_paths[0]

def test_00_input_database_unchanged():
    assert os.path.isfile(DB_PATH), f"Input database missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        accounts = conn.execute(
            "SELECT account_id, account_type, risk_score FROM accounts ORDER BY account_id"
        ).fetchall()
        transactions = conn.execute(
            "SELECT tx_id, source_account, target_account, amount FROM transactions ORDER BY tx_id"
        ).fetchall()
    finally:
        conn.close()

    assert accounts == EXPECTED_ACCOUNTS, "The supplied accounts snapshot was modified"
    assert transactions == EXPECTED_TRANSACTIONS, "The supplied transactions snapshot was modified"

def test_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON")

    assert "top_3_pagerank_accounts" in data, "Missing 'top_3_pagerank_accounts' in JSON"
    assert "shortest_illicit_path" in data, "Missing 'shortest_illicit_path' in JSON"

def test_report_values():
    accounts, edges = get_db_data()

    nodes = [acc[0] for acc in accounts]
    high_risk = [acc[0] for acc in accounts if acc[2] > 80]
    offshore = [acc[0] for acc in accounts if acc[1] == 'offshore']

    pr = compute_pagerank(nodes, edges)
    sorted_pr = sorted(pr.items(), key=lambda x: (-x[1], x[0]))
    expected_top_3 = [x[0] for x in sorted_pr[:3]]

    expected_path = find_shortest_path(nodes, edges, high_risk, offshore)

    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    assert data["top_3_pagerank_accounts"] == expected_top_3, \
        f"Expected top 3 PageRank accounts {expected_top_3}, but got {data.get('top_3_pagerank_accounts')}"

    assert data["shortest_illicit_path"] == expected_path, \
        f"Expected shortest path {expected_path}, but got {data.get('shortest_illicit_path')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
