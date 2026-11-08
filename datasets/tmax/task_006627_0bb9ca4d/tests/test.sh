#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest
from collections import defaultdict, deque

EXPECTED_SQLITE_ROWS = [
    ("TX01", "C-837", "C-500", 1000.0),
    ("TX02", "C-777", "C-500", 500.0),
    ("TX03", "C-901", "C-600", 200.0),
    ("TX04", "C-902", "C-600", 250.0),
    ("TX05", "C-903", "C-600", 300.0),
    ("TX06", "C-999", "C-837", 10000.0),
]

EXPECTED_JSON_ROWS = [
    {"transaction_id": "TX07", "from_account": "C-500", "to_account": "C-600", "transfer_value": 1500.0},
    {"transaction_id": "TX08", "from_account": "C-600", "to_account": "C-102", "transfer_value": 1400.0},
    {"transaction_id": "TX09", "from_account": "C-904", "to_account": "C-600", "transfer_value": 100.0},
    {"transaction_id": "TX10", "from_account": "C-111", "to_account": "C-222", "transfer_value": 50.0},
]

def validate_source_inputs():
    db_path = "/home/user/audit/active.sqlite"
    json_path = "/home/user/audit/archived.json"

    assert os.path.isfile(db_path), f"Required source database {db_path} is missing."
    assert os.path.isfile(json_path), f"Required archived source {json_path} is missing."

    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("SELECT tx_id, src_account, dst_account, amount FROM transfers")
        actual_sqlite_rows = cur.fetchall()
    finally:
        conn.close()

    assert sorted(actual_sqlite_rows) == sorted(EXPECTED_SQLITE_ROWS), \
        "The active transaction source was deleted or modified."

    with open(json_path, "r") as f:
        actual_json_rows = json.load(f)

    def json_key(row):
        return (
            row.get("transaction_id"),
            row.get("from_account"),
            row.get("to_account"),
            row.get("transfer_value"),
        )

    assert isinstance(actual_json_rows, list), "Archived transaction source must be a JSON array."
    assert sorted(actual_json_rows, key=json_key) == sorted(EXPECTED_JSON_ROWS, key=json_key), \
        "The archived transaction source was deleted or modified."

def compute_expected_results():
    db_path = "/home/user/audit/active.sqlite"
    json_path = "/home/user/audit/archived.json"

    validate_source_inputs()

    edges = set()
    nodes = set()

    # Read SQLite
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT src_account, dst_account FROM transfers")
        for src, dst in cur.fetchall():
            edges.add((src, dst))
            nodes.add(src)
            nodes.add(dst)
        conn.close()

    # Read JSON
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            data = json.load(f)
            for row in data:
                src = row.get("from_account")
                dst = row.get("to_account")
                if src and dst:
                    edges.add((src, dst))
                    nodes.add(src)
                    nodes.add(dst)

    # Build adjacency lists
    adj = defaultdict(list)
    in_degree = defaultdict(int)

    for src, dst in edges:
        adj[src].append(dst)
        in_degree[dst] += 1

    # Shortest path using BFS
    start = "C-837"
    target = "C-102"

    queue = deque([[start]])
    visited = set([start])
    shortest_path = []

    while queue:
        path = queue.popleft()
        node = path[-1]

        if node == target:
            shortest_path = path
            break

        for neighbor in adj[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    path_hops = len(shortest_path) - 1 if shortest_path else 0

    # In-Degree Centrality
    N = len(nodes)
    centrality = {}
    for node in nodes:
        centrality[node] = in_degree[node] / (N - 1) if N > 1 else 0

    # Bottleneck node
    bottleneck_account = None
    bottleneck_centrality = -1

    if len(shortest_path) > 2:
        for node in shortest_path[1:-1]:
            if centrality[node] > bottleneck_centrality:
                bottleneck_centrality = centrality[node]
                bottleneck_account = node

    return {
        "shortest_path": shortest_path,
        "path_hops": path_hops,
        "bottleneck_account": bottleneck_account,
        "bottleneck_centrality": round(bottleneck_centrality, 4) if bottleneck_centrality != -1 else 0.0
    }

def test_compliance_report():
    report_path = "/home/user/compliance_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected = compute_expected_results()

    assert "shortest_path" in report, "Missing 'shortest_path' in report."
    assert report["shortest_path"] == expected["shortest_path"], f"Expected shortest_path {expected['shortest_path']}, got {report['shortest_path']}"

    assert "path_hops" in report, "Missing 'path_hops' in report."
    assert report["path_hops"] == expected["path_hops"], f"Expected path_hops {expected['path_hops']}, got {report['path_hops']}"

    assert "bottleneck_account" in report, "Missing 'bottleneck_account' in report."
    assert report["bottleneck_account"] == expected["bottleneck_account"], f"Expected bottleneck_account {expected['bottleneck_account']}, got {report['bottleneck_account']}"

    assert "bottleneck_centrality" in report, "Missing 'bottleneck_centrality' in report."
    assert report["bottleneck_centrality"] == expected["bottleneck_centrality"], f"Expected bottleneck_centrality {expected['bottleneck_centrality']}, got {report['bottleneck_centrality']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
