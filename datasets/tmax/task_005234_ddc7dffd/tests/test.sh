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

import pytest

SCRIPT_PATH = '/home/user/optimize_route.py'
JSON_PATH = '/home/user/optimal_path.json'
DB_PATH = '/home/user/network.db'
EXPECTED_PATH = ["gateway-alpha", "router-b", "switch-d", "storage-omega"]


def run_submission():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def read_output():
    assert os.path.exists(JSON_PATH), f'The output file {JSON_PATH} does not exist.'
    assert os.path.isfile(JSON_PATH), f'The path {JSON_PATH} is not a file.'
    with open(JSON_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f'Failed to parse {JSON_PATH} as JSON: {e}')


def shortest_path_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        node_rows = conn.execute('SELECT node_id, hostname FROM nodes').fetchall()
        edges = conn.execute('SELECT src_node_id, dst_node_id, latency FROM links').fetchall()
    finally:
        conn.close()

    names = dict(node_rows)
    ids = {hostname: node_id for node_id, hostname in node_rows}
    adjacency = {}
    for src, dst, weight in edges:
        adjacency.setdefault(src, []).append((dst, weight))

    source = ids['gateway-alpha']
    target = ids['storage-omega']
    queue = [(0, source, [source])]
    best = {}
    while queue:
        distance, node, path = heapq.heappop(queue)
        if node in best and best[node] <= distance:
            continue
        best[node] = distance
        if node == target:
            return [names[node_id] for node_id in path]
        for neighbor, weight in adjacency.get(node, []):
            heapq.heappush(queue, (distance + weight, neighbor, path + [neighbor]))
    raise AssertionError('No route exists between the requested devices.')


def test_optimize_route_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f'The required script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'
    assert not os.path.islink(SCRIPT_PATH), f'The required script {SCRIPT_PATH} must be a regular file.'
    run_submission()


def test_optimal_path_json_exists():
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."


def test_optimal_path_json_content():
    assert os.path.exists(JSON_PATH), f"Cannot check content, {JSON_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {JSON_PATH} as JSON: {e}")

    assert isinstance(data, list), f"Expected JSON root to be a list, but got {type(data).__name__}."
    assert data == EXPECTED_PATH, f"The computed optimal path is incorrect. Expected {EXPECTED_PATH}, but got {data}."


def test_script_reads_database_and_recomputes_route():
    backup_path = '/tmp/network_verifier_backup.db'
    shutil.copy2(DB_PATH, backup_path)
    random_hostname = 'verification-node-' + secrets.token_hex(12)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            source_id = conn.execute(
                "SELECT node_id FROM nodes WHERE hostname = 'gateway-alpha'"
            ).fetchone()[0]
            target_id = conn.execute(
                "SELECT node_id FROM nodes WHERE hostname = 'storage-omega'"
            ).fetchone()[0]
            new_node_id = conn.execute('SELECT COALESCE(MAX(node_id), 0) + 1 FROM nodes').fetchone()[0]
            next_link_id = conn.execute('SELECT COALESCE(MAX(link_id), 0) + 1 FROM links').fetchone()[0]
            conn.execute(
                'INSERT INTO nodes(node_id, hostname, device_type) VALUES (?, ?, ?)',
                (new_node_id, random_hostname, 'verification'),
            )
            conn.execute(
                'INSERT INTO links(link_id, src_node_id, dst_node_id, latency) VALUES (?, ?, ?, ?)',
                (next_link_id, source_id, new_node_id, 1),
            )
            conn.execute(
                'INSERT INTO links(link_id, src_node_id, dst_node_id, latency) VALUES (?, ?, ?, ?)',
                (next_link_id + 1, new_node_id, target_id, 1),
            )
            conn.commit()
        finally:
            conn.close()

        expected = shortest_path_from_database()
        assert random_hostname in expected
        run_submission()
        data = read_output()
        assert isinstance(data, list), f'Expected JSON root to be a list, but got {type(data).__name__}.'
        assert data == expected, (
            'The script did not recompute the shortest directed route from the modified database. '
            f'Expected {expected}, but got {data}.'
        )
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if os.path.isfile(SCRIPT_PATH):
            subprocess.run(
                ['python3', SCRIPT_PATH],
                cwd='/home/user',
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
