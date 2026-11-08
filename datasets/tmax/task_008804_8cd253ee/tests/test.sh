#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

REPORT_PATH = '/home/user/report.json'
DB_PATH = '/home/user/audit.db'

def test_report_exists():
    """Verify that the report.json file has been created."""
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist."

def test_report_content():
    """Verify the logic and correct answers in the report.json file."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Fetch all GRANTED and WAITING locks
    c.execute("SELECT pid, resource FROM db_locks WHERE status='GRANTED'")
    granted = c.fetchall()

    c.execute("SELECT pid, resource FROM db_locks WHERE status='WAITING'")
    waiting = c.fetchall()

    # Build the dependency graph edges and nodes
    edges = []
    nodes = set()

    # Add nodes from both granted and waiting
    for pid, _ in granted:
        nodes.add(pid)
    for pid, _ in waiting:
        nodes.add(pid)

    for w_pid, w_res in waiting:
        for g_pid, g_res in granted:
            if w_res == g_res:
                edges.append((w_pid, g_pid))

    # 1. Compute PageRank
    N = len(nodes)
    if N > 0:
        pr = {n: 1.0 / N for n in nodes}
        out_degree = {n: 0 for n in nodes}
        for u, v in edges:
            out_degree[u] += 1

        d = 0.85
        # 100 iterations is plenty for this small graph to converge
        for _ in range(100):
            new_pr = {}
            dangling_sum = sum(pr[n] for n in nodes if out_degree[n] == 0)
            for n in nodes:
                incoming_sum = sum(pr[u] / out_degree[u] for u, v in edges if v == n)
                new_pr[n] = (1 - d) / N + d * incoming_sum + d * dangling_sum / N
            pr = new_pr

        expected_highest_pr_pid = max(pr, key=pr.get)
    else:
        expected_highest_pr_pid = None

    # 2. Find the deadlock cycle containing the highest-PageRank PID
    graph = {n: [] for n in nodes}
    for u, v in edges:
        graph[u].append(v)

    def find_cycle_containing(start):
        if start is None:
            return []

        path = [start]
        in_path = {start}

        def dfs(node):
            for neighbor in graph[node]:
                if neighbor == start:
                    return list(path)
                if neighbor not in in_path:
                    path.append(neighbor)
                    in_path.add(neighbor)
                    cycle = dfs(neighbor)
                    if cycle:
                        return cycle
                    in_path.remove(neighbor)
                    path.pop()
            return None

        cycle = dfs(start)
        return sorted(cycle) if cycle else []

    expected_cycle = find_cycle_containing(expected_highest_pr_pid)

    # 3. Find Top Hoarder
    c.execute("""
        SELECT pid, COUNT(*) as cnt
        FROM db_locks
        WHERE status='GRANTED'
        GROUP BY pid
        ORDER BY cnt DESC, pid ASC
        LIMIT 1
    """)
    hoarder_row = c.fetchone()
    expected_hoarder = hoarder_row[0] if hoarder_row else None

    conn.close()

    # Read and parse the report
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON.")

    # Validate structure
    assert "deadlock_cycle_pids" in report, "Missing 'deadlock_cycle_pids' in report.json."
    assert "highest_pagerank_pid" in report, "Missing 'highest_pagerank_pid' in report.json."
    assert "top_ranked_hoarder_pid" in report, "Missing 'top_ranked_hoarder_pid' in report.json."

    # Validate values
    assert report["deadlock_cycle_pids"] == expected_cycle, \
        f"Expected deadlock cycle PIDs {expected_cycle}, but got {report['deadlock_cycle_pids']}."

    assert report["highest_pagerank_pid"] == expected_highest_pr_pid, \
        f"Expected highest PageRank PID {expected_highest_pr_pid}, but got {report['highest_pagerank_pid']}."

    assert report["top_ranked_hoarder_pid"] == expected_hoarder, \
        f"Expected top ranked hoarder PID {expected_hoarder}, but got {report['top_ranked_hoarder_pid']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
