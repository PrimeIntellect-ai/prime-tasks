#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import sqlite3
import subprocess
import secrets
import pytest
from collections import deque

HOME = '/home/user'
ETL_PATH = os.path.join(HOME, 'etl_pipeline.py')
CSV_PATH = os.path.join(HOME, 'edges.csv')
JSON_PATH = os.path.join(HOME, 'final_output.json')


def get_expected_data():
    conn = sqlite3.connect('/home/user/data.db')
    c = conn.cursor()

    query = """
    SELECT
        u1.user_id AS sender,
        u2.user_id AS receiver,
        t.amount,
        t.timestamp,
        SUM(t.amount) OVER (
            PARTITION BY t.sender
            ORDER BY t.timestamp ASC
        ) AS cumulative_sent
    FROM transactions t
    JOIN users u1 ON u1.user_id = t.sender
    JOIN users u2 ON u2.user_id = t.receiver
    ORDER BY t.tx_id ASC
    """
    c.execute(query)
    rows = c.fetchall()
    conn.close()
    return rows


def compute_shortest_path(edges, start_node, end_node):
    graph = {}
    for sender, receiver, _, _, _ in edges:
        if sender not in graph:
            graph[sender] = []
        graph[sender].append(receiver)

    queue = deque([[start_node]])
    visited = set([start_node])

    while queue:
        path = queue.popleft()
        node = path[-1]

        if node == end_node:
            return path

        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                new_path = list(path)
                new_path.append(neighbor)
                queue.append(new_path)

    return None


def test_00_execute_corrected_pipeline_and_new_analysis_script():
    assert os.path.isfile(ETL_PATH), f'{ETL_PATH} does not exist or is not a regular file.'
    assert not os.path.islink(ETL_PATH), f'{ETL_PATH} must not be a symlink.'

    with open(ETL_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    assert re.search(r'\bSUM\s*\([^)]*amount[^)]*\)\s*OVER\s*\(', source, re.I | re.S), \
        'etl_pipeline.py must contain a SQL SUM window function for amount.'
    assert re.search(r'\bPARTITION\s+BY\b', source, re.I), \
        'The SQL window must partition cumulative totals by sender.'
    assert re.search(r'\bORDER\s+BY\b', source, re.I), \
        'The SQL window must order the running total by timestamp.'
    assert re.search(r'\bcumulative_sent\b', source, re.I), \
        'The SQL query must produce cumulative_sent.'

    # Add an unpredictable challenge after the agent has finished. The direct edge
    # changes the shortest path, the amounts change cumulative totals, and the two
    # invalid transactions ensure both users-table joins are actually enforced.
    conn = sqlite3.connect('/home/user/data.db')
    c = conn.cursor()
    changed_amount = float(secrets.randbelow(90000) + 10001) / 10.0
    user9_amount = float(secrets.randbelow(90000) + 10001) / 10.0
    c.execute('UPDATE transactions SET amount = ? WHERE tx_id = 1', (changed_amount,))
    next_id = c.execute('SELECT COALESCE(MAX(tx_id), 0) + 1 FROM transactions').fetchone()[0]
    c.execute(
        'INSERT INTO transactions VALUES (?, ?, ?, ?, ?)',
        (next_id, 'user_1', 'user_9', 7.25, '2023-01-07T10:00:00')
    )
    c.execute(
        'INSERT INTO transactions VALUES (?, ?, ?, ?, ?)',
        (next_id + 1, 'user_9', 'user_4', user9_amount, '2023-01-08T10:00:00')
    )
    c.execute(
        'INSERT INTO transactions VALUES (?, ?, ?, ?, ?)',
        (next_id + 2, 'not_a_user', 'user_9', 999999.0, '2023-01-09T10:00:00')
    )
    c.execute(
        'INSERT INTO transactions VALUES (?, ?, ?, ?, ?)',
        (next_id + 3, 'user_9', 'not_a_user', 999999.0, '2023-01-10T10:00:00')
    )
    conn.commit()
    conn.close()

    for output in (CSV_PATH, JSON_PATH):
        if os.path.lexists(output):
            os.remove(output)

    etl = subprocess.run(
        ['python3', ETL_PATH], cwd=HOME, capture_output=True, text=True, timeout=20
    )
    assert etl.returncode == 0, \
        f'etl_pipeline.py failed when executed from /home/user:\n{etl.stdout}\n{etl.stderr}'
    assert os.path.isfile(CSV_PATH), 'Executing etl_pipeline.py did not create edges.csv.'

    candidates = []
    for name in os.listdir(HOME):
        path = os.path.join(HOME, name)
        if name.endswith('.py') and path != ETL_PATH and os.path.isfile(path) and not os.path.islink(path):
            candidates.append(path)
    assert candidates, 'No new Python script for the directed shortest-path analysis was found.'

    produced_by = None
    failures = []
    for script in sorted(candidates):
        if os.path.lexists(JSON_PATH):
            os.remove(JSON_PATH)
        try:
            result = subprocess.run(
                ['python3', script], cwd=HOME, capture_output=True, text=True, timeout=20
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue
        if result.returncode == 0 and os.path.isfile(JSON_PATH):
            produced_by = script
            break
        failures.append(f'{script}: exit={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}')

    assert produced_by is not None, \
        'No new analysis script successfully created final_output.json when executed from /home/user. ' + '; '.join(failures)


def test_edges_csv_exists_and_correct():
    csv_path = '/home/user/edges.csv'
    assert os.path.exists(csv_path), f"{csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        expected_header = ['sender', 'receiver', 'amount', 'timestamp', 'cumulative_sent']
        assert header == expected_header, f"Expected header {expected_header}, got {header}"

        rows = list(reader)

    expected_rows = get_expected_data()
    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, got {len(rows)}"

    # Check data correctness (ignoring order)
    expected_set = set()
    for r in expected_rows:
        expected_set.add((str(r[0]), str(r[1]), float(r[2]), str(r[3]), float(r[4])))

    actual_set = set()
    for r in rows:
        actual_set.add((str(r[0]), str(r[1]), float(r[2]), str(r[3]), float(r[4])))

    assert actual_set == expected_set, "Data in edges.csv does not match expected output."


def test_final_output_json():
    json_path = '/home/user/final_output.json'
    assert os.path.exists(json_path), f"{json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON.")

    assert "shortest_path" in data, "Key 'shortest_path' missing in final_output.json"
    assert "user_9_max_cumulative_sent" in data, "Key 'user_9_max_cumulative_sent' missing in final_output.json"

    expected_rows = get_expected_data()
    expected_path = compute_shortest_path(expected_rows, 'user_1', 'user_9')

    user_9_cumulative_sents = [r[4] for r in expected_rows if r[0] == 'user_9']
    expected_max_cumulative = max(user_9_cumulative_sents) if user_9_cumulative_sents else 0.0

    assert data["shortest_path"] == expected_path, f"Expected shortest_path {expected_path}, got {data['shortest_path']}"
    assert float(data["user_9_max_cumulative_sent"]) == expected_max_cumulative, f"Expected user_9_max_cumulative_sent {expected_max_cumulative}, got {data['user_9_max_cumulative_sent']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
