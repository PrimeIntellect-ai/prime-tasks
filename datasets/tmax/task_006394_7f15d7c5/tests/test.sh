#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

DB_PATH = '/home/user/corporate_data.db'
REPORTS_FILE = '/home/user/reports_chain.txt'
BOTTLENECK_FILE = '/home/user/bottleneck_project.txt'

def test_reports_chain():
    assert os.path.exists(REPORTS_FILE), f"File {REPORTS_FILE} is missing."

    # Derive the expected reports chain from the database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE subordinates AS (
        SELECT emp_id FROM employees WHERE emp_id = 'E001'
        UNION ALL
        SELECT e.emp_id FROM employees e
        INNER JOIN subordinates s ON e.manager_id = s.emp_id
    )
    SELECT emp_id FROM subordinates ORDER BY emp_id;
    """
    cursor.execute(query)
    expected_chain = [row[0] for row in cursor.fetchall()]
    conn.close()

    with open(REPORTS_FILE, 'r') as f:
        actual_chain = [line.strip() for line in f if line.strip()]

    assert actual_chain == expected_chain, (
        f"Contents of {REPORTS_FILE} do not match the expected hierarchy. "
        f"Expected {expected_chain}, got {actual_chain}."
    )

def test_bottleneck_project():
    assert os.path.exists(BOTTLENECK_FILE), f"File {BOTTLENECK_FILE} is missing."

    # Derive the expected bottleneck project using PageRank
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT depends_on_project_id, project_id FROM project_dependencies")
    edges = cursor.fetchall()
    conn.close()

    # Get all unique nodes
    nodes = set()
    for u, v in edges:
        nodes.add(u)
        nodes.add(v)

    # Simple PageRank implementation (equivalent to networkx default)
    N = len(nodes)
    assert N > 0, "No projects found in database."

    pr = {n: 1.0 / N for n in nodes}
    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    d = 0.85
    for _ in range(100):
        new_pr = {n: (1.0 - d) / N for n in nodes}
        sink_rank = sum(pr[n] for n in nodes if out_degree[n] == 0)

        for n in nodes:
            new_pr[n] += d * sink_rank / N

        for u, v in edges:
            new_pr[v] += d * pr[u] / out_degree[u]

        pr = new_pr

    expected_bottleneck = max(pr.items(), key=lambda x: x[1])[0]

    with open(BOTTLENECK_FILE, 'r') as f:
        actual_bottleneck = f.read().strip()

    assert actual_bottleneck == expected_bottleneck, (
        f"Contents of {BOTTLENECK_FILE} do not match the expected bottleneck project. "
        f"Expected {expected_bottleneck}, got {actual_bottleneck}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
