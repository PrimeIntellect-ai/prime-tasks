#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = '/home/user/backup_metadata.db'
SCRIPT_PATH = '/home/user/analyze_failures.py'
OUTPUT_JSON_PATH = '/home/user/failed_downstream.json'


def run_script():
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'Script failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT_JSON_PATH), f'Output file {OUTPUT_JSON_PATH} does not exist.'
    with open(OUTPUT_JSON_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'File {OUTPUT_JSON_PATH} does not contain valid JSON: {exc}')


def test_script_exists_is_executable_and_initial_output_is_correct():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script {SCRIPT_PATH} is not executable.'

    data = run_script()
    expected_data = ['export_job_s3', 'table_orders', 'view_daily_sales']
    assert isinstance(data, list), 'JSON output should be a list.'
    assert data == expected_data, f'JSON output {data} does not match expected {expected_data}.'


def index_columns(cursor, index_name):
    escaped = index_name.replace('"', '""')
    cursor.execute(f'PRAGMA index_info("{escaped}")')
    return [row[2] for row in cursor.fetchall()]


def test_database_indexes_created_on_required_columns():
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} does not exist.'

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges';")
    edges_indexes = cursor.fetchall()
    assert len(edges_indexes) > 0, "No indexes found on the 'edges' table."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='backup_runs';")
    backup_runs_indexes = cursor.fetchall()
    assert len(backup_runs_indexes) > 0, "No indexes found on the 'backup_runs' table."

    cursor.execute("PRAGMA index_list('edges')")
    usable_edge_indexes = [row[1] for row in cursor.fetchall() if row[4] == 0]
    assert any(index_columns(cursor, name)[:1] == ['source_id'] for name in usable_edge_indexes), (
        "The edges table needs a non-partial index whose leading column is source_id."
    )

    cursor.execute("PRAGMA index_list('backup_runs')")
    usable_run_indexes = [row[1] for row in cursor.fetchall() if row[4] == 0]
    assert any(index_columns(cursor, name)[:2] == ['node_id', 'run_time'] for name in usable_run_indexes), (
        "The backup_runs table needs a non-partial composite index beginning with node_id, run_time."
    )
    conn.close()


def independently_expected(nodes, edges, runs):
    root_ids = [node_id for node_id, name, _ in nodes if name == 'db_sales']
    assert len(root_ids) == 1
    root_id = root_ids[0]

    adjacency = {}
    for source_id, target_id in edges:
        adjacency.setdefault(source_id, []).append(target_id)

    reachable = set()
    pending = list(adjacency.get(root_id, []))
    while pending:
        node_id = pending.pop()
        if node_id == root_id or node_id in reachable:
            continue
        reachable.add(node_id)
        pending.extend(adjacency.get(node_id, []))

    latest = {}
    for _, node_id, run_time, status in runs:
        if node_id not in latest or run_time > latest[node_id][0]:
            latest[node_id] = (run_time, status)

    names = {node_id: name for node_id, name, _ in nodes}
    return sorted(
        names[node_id]
        for node_id in reachable
        if node_id in latest and latest[node_id][1] == 'FAILED'
    )


def test_script_traverses_unseen_graph_and_computes_latest_statuses():
    token = secrets.token_hex(5)
    root_id = 1001
    chain_ids = list(range(1002, 1017))
    branch_id = 1100
    unrelated_root = 1200
    unrelated_child = 1201

    nodes = [(root_id, 'db_sales', 'database')]
    nodes += [
        (node_id, f'{token}_chain_{i:02d}', 'job')
        for i, node_id in enumerate(chain_ids, start=1)
    ]
    nodes += [
        (branch_id, f'{token}_branch', 'job'),
        (unrelated_root, f'{token}_unrelated_root', 'database'),
        (unrelated_child, f'{token}_unrelated_failed', 'job'),
    ]

    edges = [(root_id, chain_ids[0])]
    edges += list(zip(chain_ids[:-1], chain_ids[1:]))
    edges += [
        (chain_ids[2], chain_ids[7]),
        (chain_ids[3], branch_id),
        (unrelated_root, unrelated_child),
    ]

    runs = []
    run_id = 1
    runs.append((run_id, root_id, '2041-01-03 00:00:00', 'FAILED'))
    run_id += 1
    for i, node_id in enumerate(chain_ids, start=1):
        runs.append((run_id, node_id, '2041-01-01 00:00:00', 'FAILED'))
        run_id += 1
        if i != 5:
            if i == 4:
                latest_status = 'failed'
            else:
                latest_status = 'FAILED' if i % 3 == 0 else 'SUCCESS'
            runs.append((run_id, node_id, '2041-01-02 00:00:00', latest_status))
            run_id += 1
    runs.append((run_id, branch_id, '2041-01-04 00:00:00', 'FAILED'))
    run_id += 1
    runs.append((run_id, unrelated_child, '2041-01-05 00:00:00', 'FAILED'))

    expected = independently_expected(nodes, edges, runs)

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute('DELETE FROM backup_runs')
        cursor.execute('DELETE FROM edges')
        cursor.execute('DELETE FROM nodes')
        cursor.executemany('INSERT INTO nodes (id, name, type) VALUES (?, ?, ?)', nodes)
        cursor.executemany('INSERT INTO edges (source_id, target_id) VALUES (?, ?)', edges)
        cursor.executemany(
            'INSERT INTO backup_runs (id, node_id, run_time, status) VALUES (?, ?, ?, ?)',
            runs,
        )
        conn.commit()
    finally:
        conn.close()

    data = run_script()
    assert isinstance(data, list), 'JSON output should be a list.'
    assert data == expected, f'For the unseen graph, output {data} does not match derived result {expected}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
