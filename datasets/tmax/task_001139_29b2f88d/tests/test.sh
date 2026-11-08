#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
from collections import defaultdict, deque
import pytest

def compute_critical_path(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    c.execute("SELECT id, name, backup_time FROM databases")
    nodes = c.fetchall()

    backup_times = {}
    names = {}
    for node_id, name, bt in nodes:
        backup_times[node_id] = bt
        names[node_id] = name

    c.execute("SELECT source_id, target_id FROM dependencies")
    edges = c.fetchall()
    conn.close()

    adj = defaultdict(list)
    in_degree = {node_id: 0 for node_id in backup_times}

    for u, v in edges:
        adj[u].append(v)
        in_degree[v] += 1

    q = deque([n for n in backup_times if in_degree[n] == 0])
    topo_order = []

    while q:
        curr = q.popleft()
        topo_order.append(curr)
        for nxt in adj[curr]:
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                q.append(nxt)

    dist = {n: backup_times[n] for n in backup_times}
    parent = {n: -1 for n in backup_times}

    for u in topo_order:
        for v in adj[u]:
            if dist[u] + backup_times[v] > dist[v]:
                dist[v] = dist[u] + backup_times[v]
                parent[v] = u

    max_dist = 0
    end_node = -1
    for n in backup_times:
        if dist[n] > max_dist:
            max_dist = dist[n]
            end_node = n

    path = []
    curr = end_node
    while curr != -1:
        path.append(curr)
        curr = parent[curr]
    path.reverse()

    path_names = [names[n] for n in path]

    return max_dist, path_names

def test_critical_path_time():
    db_path = "/home/user/backup_deps.db"
    time_file = "/home/user/critical_path_time.txt"

    assert os.path.exists(db_path), f"Database missing at {db_path}"
    assert os.path.exists(time_file), f"Output file missing: {time_file}"

    expected_time, _ = compute_critical_path(db_path)

    with open(time_file, "r") as f:
        student_time_str = f.read().strip()

    assert student_time_str.isdigit(), f"Content of {time_file} is not a valid integer: '{student_time_str}'"
    assert int(student_time_str) == expected_time, f"Critical path time is incorrect. Expected {expected_time}, got {student_time_str}"

def test_critical_path_sequence():
    db_path = "/home/user/backup_deps.db"
    seq_file = "/home/user/critical_path_sequence.txt"

    assert os.path.exists(db_path), f"Database missing at {db_path}"
    assert os.path.exists(seq_file), f"Output file missing: {seq_file}"

    _, expected_sequence_list = compute_critical_path(db_path)
    expected_sequence = ",".join(expected_sequence_list)

    with open(seq_file, "r") as f:
        student_sequence = f.read().strip()

    assert student_sequence == expected_sequence, f"Critical path sequence is incorrect.\nExpected: {expected_sequence}\nGot: {student_sequence}"

def test_query_plan():
    plan_file = "/home/user/query_plan.txt"

    assert os.path.exists(plan_file), f"Output file missing: {plan_file}"

    with open(plan_file, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"Query plan file {plan_file} is empty."

    upper_content = content.upper()
    assert "SCAN" in upper_content or "SEARCH" in upper_content, \
        f"Query plan file {plan_file} does not appear to contain a valid EXPLAIN QUERY PLAN output (missing SCAN or SEARCH keywords)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
