#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import pytest

SCRIPT_PATH = '/home/user/analyze_routing.py'
RESULT_PATH = '/home/user/routing_result.json'
DB_PATH = '/home/user/db_topology.db'


def load_result():
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {RESULT_PATH}: {e}")


def run_script():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {completed.returncode}. "
        f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
    )
    assert os.path.exists(RESULT_PATH), f"Output file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file."


def shortest_path_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            SELECT s.name, t.name, e.latency_ms
            FROM edges e
            JOIN nodes s ON s.id = e.source_id
            JOIN nodes t ON t.id = e.target_id
        ''').fetchall()
    finally:
        conn.close()

    graph = {}
    for source, target, latency in rows:
        graph.setdefault(source, []).append((target, latency))

    queue = [(0, 'API_Gateway', ['API_Gateway'])]
    best = {'API_Gateway': 0}
    while queue:
        latency, node, path = heapq.heappop(queue)
        if latency != best.get(node):
            continue
        if node == 'User_Master':
            return latency, path
        for target, edge_latency in graph.get(node, []):
            candidate = latency + edge_latency
            if candidate < best.get(target, float('inf')):
                best[target] = candidate
                heapq.heappush(queue, (candidate, target, path + [target]))
    pytest.fail("No path from API_Gateway to User_Master exists in the test database.")


def install_randomized_database():
    nodes = [
        (1, 'API_Gateway', 'service'),
        (2, 'Auth_Service', 'service'),
        (3, 'Cache_Layer', 'cache'),
        (4, 'User_ReadReplica', 'database'),
        (5, 'User_Master', 'database'),
        (6, 'Billing_Service', 'service'),
        (7, 'Message_Queue', 'queue'),
    ]

    while True:
        weights = [secrets.randbelow(90) + 1 for _ in range(9)]
        route_totals = [
            weights[0] + weights[1] + weights[3],
            weights[2] + weights[3] + weights[4],
            weights[5] + weights[6],
            weights[7] + weights[8],
        ]
        if len(set(route_totals)) == len(route_totals):
            break

    edges = [
        (1, 2, weights[0], 'rpc'),
        (2, 4, weights[1], 'sql'),
        (1, 3, weights[2], 'tcp'),
        (4, 5, weights[3], 'replication'),
        (3, 4, weights[4], 'sql'),
        (1, 6, weights[5], 'rpc'),
        (6, 5, weights[6], 'sql'),
        (1, 7, weights[7], 'amqp'),
        (7, 5, weights[8], 'worker'),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('''CREATE TABLE nodes (
            id INTEGER PRIMARY KEY,
            name TEXT UNIQUE,
            node_type TEXT
        )''')
        conn.execute('''CREATE TABLE edges (
            source_id INTEGER,
            target_id INTEGER,
            latency_ms INTEGER,
            connection_type TEXT,
            FOREIGN KEY(source_id) REFERENCES nodes(id),
            FOREIGN KEY(target_id) REFERENCES nodes(id)
        )''')
        conn.executemany('INSERT INTO nodes VALUES (?, ?, ?)', nodes)
        conn.executemany('INSERT INTO edges VALUES (?, ?, ?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def test_analyzer_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."


def test_routing_result_exists():
    assert os.path.exists(RESULT_PATH), f"Output file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file."


def test_routing_result_contents():
    data = load_result()

    assert "source" in data, "Missing 'source' key in JSON output."
    assert data["source"] == "API_Gateway", f"Expected source to be 'API_Gateway', got {data['source']}"

    assert "destination" in data, "Missing 'destination' key in JSON output."
    assert data["destination"] == "User_Master", f"Expected destination to be 'User_Master', got {data['destination']}"

    assert "total_latency_ms" in data, "Missing 'total_latency_ms' key in JSON output."
    assert isinstance(data["total_latency_ms"], int), "'total_latency_ms' must be an integer."
    assert data["total_latency_ms"] == 22, f"Expected total_latency_ms to be 22, got {data['total_latency_ms']}"

    assert "path_nodes" in data, "Missing 'path_nodes' key in JSON output."
    assert isinstance(data["path_nodes"], list), "'path_nodes' must be a list."

    expected_path = ["API_Gateway", "Message_Queue", "User_Master"]
    assert data["path_nodes"] == expected_path, f"Expected path_nodes to be {expected_path}, got {data['path_nodes']}"


def test_script_queries_database_and_computes_shortest_path():
    run_script()
    original = load_result()
    assert original["source"] == "API_Gateway"
    assert original["destination"] == "User_Master"
    assert original["total_latency_ms"] == 22
    assert original["path_nodes"] == ["API_Gateway", "Message_Queue", "User_Master"]

    fd, backup_path = tempfile.mkstemp(prefix='db_topology_backup_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        install_randomized_database()
        expected_latency, expected_path = shortest_path_from_database()

        run_script()
        data = load_result()
        assert data["source"] == "API_Gateway"
        assert data["destination"] == "User_Master"
        assert isinstance(data["total_latency_ms"], int), "'total_latency_ms' must be an integer."
        assert data["total_latency_ms"] == expected_latency, (
            f"Expected computed latency {expected_latency}, got {data['total_latency_ms']}"
        )
        assert isinstance(data["path_nodes"], list), "'path_nodes' must be a list."
        assert data["path_nodes"] == expected_path, (
            f"Expected computed path {expected_path}, got {data['path_nodes']}"
        )
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.move(backup_path, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
