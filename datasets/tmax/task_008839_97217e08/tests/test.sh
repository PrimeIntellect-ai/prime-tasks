#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

SCRIPT_PATH = '/home/user/etl_router.py'
DB_PATH = '/home/user/supply_chain.db'
CSV_PATH = '/home/user/optimal_path.csv'
JSON_PATH = '/home/user/path_summary.json'
QUERY_PLAN_PATH = '/home/user/query_plan.txt'
OUTPUT_PATHS = (CSV_PATH, JSON_PATH, QUERY_PLAN_PATH)


def run_submission():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'etl_router.py failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f'Python script not found at {SCRIPT_PATH}'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'Python script {SCRIPT_PATH} is empty'

    with open(SCRIPT_PATH, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    assert re.search(r'EXPLAIN\s+QUERY\s+PLAN', source, re.IGNORECASE), (
        'etl_router.py does not issue an EXPLAIN QUERY PLAN query'
    )

    # Remove pre-created artifacts so the executable submission must generate them.
    for path in OUTPUT_PATHS:
        if os.path.lexists(path):
            os.remove(path)
    run_submission()


def read_csv_rows():
    assert os.path.exists(CSV_PATH), f'CSV file not found at {CSV_PATH}'
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        return [row for row in csv.reader(f) if row]


def read_json_summary():
    assert os.path.exists(JSON_PATH), f'JSON file not found at {JSON_PATH}'
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {JSON_PATH} is not valid JSON.')


def assert_valid_query_plan():
    assert os.path.exists(QUERY_PLAN_PATH), f'Query plan file not found at {QUERY_PLAN_PATH}'
    assert os.path.getsize(QUERY_PLAN_PATH) > 0, f'Query plan file {QUERY_PLAN_PATH} is empty'
    with open(QUERY_PLAN_PATH, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()

    # SQLite EXPLAIN QUERY PLAN rows have three numeric columns followed by a
    # detail column. Accept common Python tuple/CSV and sqlite3 pipe formats.
    row_pattern = re.compile(
        r'[\[(]*\s*\d+\s*(?:,|\|)\s*\d+\s*(?:,|\|)\s*\d+\s*'
        r'(?:,|\|)\s*[\'\"]?[^\n\]\)]*'
        r'\b(?:SCAN|SEARCH|CO-ROUTINE|USE TEMP B-TREE)\b',
        re.IGNORECASE,
    )
    assert row_pattern.search(text), (
        'query_plan.txt does not contain recognizable SQLite EXPLAIN QUERY PLAN rows'
    )


def test_optimal_path_csv():
    """Verify that optimal_path.csv exists and has the correct content."""
    expected_rows = [
        ['step_number', 'location_name', 'cumulative_cost'],
        ['1', 'Alpha_Manufacturing', '0'],
        ['2', 'Beta_Hub', '10'],
        ['3', 'Gamma_Depot', '25'],
        ['4', 'Omega_Distribution', '45'],
    ]
    actual_rows = read_csv_rows()
    assert actual_rows == expected_rows, (
        f'CSV content does not match expected output. Actual: {actual_rows}'
    )


def test_path_summary_json():
    """Verify that path_summary.json exists and has the correct content."""
    expected_json = {
        'total_cost': 45,
        'hop_count': 3,
        'path': [
            'Alpha_Manufacturing',
            'Beta_Hub',
            'Gamma_Depot',
            'Omega_Distribution',
        ],
    }
    actual_json = read_json_summary()
    assert actual_json == expected_json, (
        f'JSON content does not match expected output. Actual: {actual_json}'
    )


def test_query_plan():
    """Verify that query_plan.txt contains SQLite query-plan output."""
    assert_valid_query_plan()


def derive_expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            SELECT sf.name, df.name, l.cost
            FROM links AS l
            JOIN facilities AS sf ON sf.id = l.src_id
            JOIN facilities AS df ON df.id = l.dst_id
            WHERE l.is_active = 1
        ''').fetchall()
    finally:
        conn.close()

    graph = {}
    for src, dst, cost in rows:
        graph.setdefault(src, []).append((dst, int(cost)))

    start = 'Alpha_Manufacturing'
    goal = 'Omega_Distribution'
    queue = [(0, start, [start], [0])]
    best = {}
    while queue:
        cost, node, path, cumulative = heapq.heappop(queue)
        if node in best and best[node] <= cost:
            continue
        best[node] = cost
        if node == goal:
            return path, cumulative, cost
        for neighbor, edge_cost in graph.get(node, []):
            new_cost = cost + edge_cost
            if neighbor not in best or new_cost < best[neighbor]:
                heapq.heappush(
                    queue,
                    (new_cost, neighbor, path + [neighbor], cumulative + [new_cost]),
                )
    pytest.fail('Verifier-generated active graph unexpectedly has no route')


def test_z_script_recomputes_for_changed_database():
    """Exercise the submitted pathfinder on non-fixed link costs."""
    backup_dir = tempfile.mkdtemp(prefix='etl-verifier-')
    db_backup = os.path.join(backup_dir, 'supply_chain.db')
    shutil.copy2(DB_PATH, db_backup)
    saved_outputs = {}
    for path in OUTPUT_PATHS:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                saved_outputs[path] = f.read()

    try:
        # Randomize every active route while preserving the documented schema,
        # endpoints, and inactive shortcuts. Ensure the optimum is unique and
        # cannot equal the original fixed total.
        while True:
            costs = [10 + secrets.randbelow(90) for _ in range(5)]
            route_one = costs[0] + costs[1] + costs[2]
            route_two = costs[3] + costs[4]
            if route_one != route_two and min(route_one, route_two) != 45:
                break

        conn = sqlite3.connect(DB_PATH)
        try:
            for link_id, cost in enumerate(costs, start=1):
                conn.execute(
                    'UPDATE links SET cost = ?, is_active = 1 WHERE id = ?',
                    (cost, link_id),
                )
            conn.execute('UPDATE links SET cost = 1, is_active = 0 WHERE id IN (6, 7)')
            conn.commit()
        finally:
            conn.close()

        expected_path, expected_cumulative, expected_total = derive_expected_from_database()
        for path in OUTPUT_PATHS:
            if os.path.lexists(path):
                os.remove(path)
        run_submission()

        expected_rows = [['step_number', 'location_name', 'cumulative_cost']]
        expected_rows.extend([
            [str(index), name, str(cost)]
            for index, (name, cost) in enumerate(
                zip(expected_path, expected_cumulative), start=1
            )
        ])
        assert read_csv_rows() == expected_rows, (
            'etl_router.py did not recompute the CSV shortest path from the changed database'
        )

        expected_json = {
            'total_cost': expected_total,
            'hop_count': len(expected_path) - 1,
            'path': expected_path,
        }
        assert read_json_summary() == expected_json, (
            'etl_router.py did not recompute the JSON shortest path from the changed database'
        )
        assert_valid_query_plan()
    finally:
        shutil.copy2(db_backup, DB_PATH)
        for path in OUTPUT_PATHS:
            if os.path.lexists(path):
                os.remove(path)
            if path in saved_outputs:
                with open(path, 'wb') as f:
                    f.write(saved_outputs[path])
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
