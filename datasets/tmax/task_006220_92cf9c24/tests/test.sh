#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import json
import pytest

DB_PATH = "/home/user/network.db"
REPORT_PATH = "/home/user/bottleneck_report.json"

def compute_expected_totals(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT src, dst, bandwidth FROM links")
    links = cursor.fetchall()
    conn.close()

    adj = {}
    for src, dst, bw in links:
        if src not in adj:
            adj[src] = {}
        adj[src][dst] = bw

    cycles = {}
    for a in adj:
        for b in adj[a]:
            for c in adj.get(b, {}):
                if a in adj.get(c, {}):
                    # Found cycle a->b->c->a
                    cycle_nodes = tuple(sorted([a, b, c]))
                    if len(set(cycle_nodes)) == 3:
                        bw = min(adj[a][b], adj[b][c], adj[c][a])
                        cycles[cycle_nodes] = bw

    totals = {}
    for cycle_nodes, bw in cycles.items():
        for node in cycle_nodes:
            totals[str(node)] = totals.get(str(node), 0) + bw

    return {k: v for k, v in totals.items() if v > 0}

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist. Did you run your script?"

def test_report_content():
    assert os.path.isfile(REPORT_PATH), f"Cannot test content, {REPORT_PATH} is missing."

    with open(REPORT_PATH, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file.")

    expected_data = compute_expected_totals(DB_PATH)

    assert isinstance(report_data, dict), "The JSON report should be a dictionary."
    assert report_data == expected_data, f"The contents of the report do not match the expected values. Expected {expected_data}, got {report_data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
