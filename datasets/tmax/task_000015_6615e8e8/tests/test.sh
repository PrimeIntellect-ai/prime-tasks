#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import math
import os
import sqlite3
import subprocess
import time
import urllib.parse
import urllib.request
import pytest

DB_PATH = '/app/data/routes.db'


def expected_results_from_routes():
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute('SELECT source, destination, cost FROM routes').fetchall()
    conn.close()

    graph = {}
    nodes = set()
    for source, destination, cost in rows:
        graph.setdefault(source, []).append((destination, float(cost)))
        nodes.add(source)
        nodes.add(destination)

    distances = {'WH_ALPHA': 0.0}
    queue = [(0.0, 'WH_ALPHA')]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        for destination, cost in graph.get(node, []):
            candidate = distance + cost
            if candidate < distances.get(destination, float('inf')):
                distances[destination] = candidate
                heapq.heappush(queue, (candidate, destination))

    ordered = sorted(
        ((node, cost) for node, cost in distances.items() if node.startswith('STORE_')),
        key=lambda item: (item[1], item[0]),
    )
    return [
        {'destination': destination, 'total_cost': cost, 'rank': rank}
        for rank, (destination, cost) in enumerate(ordered, 1)
    ]


def numeric_values(value):
    if isinstance(value, bool):
        return []
    if isinstance(value, (int, float)):
        return [float(value)]
    if isinstance(value, list):
        result = []
        for item in value:
            result.extend(numeric_values(item))
        return result
    if isinstance(value, dict):
        result = []
        for item in value.values():
            result.extend(numeric_values(item))
        return result
    return []


def test_analyze_script_exists():
    assert os.path.isfile('/home/user/analyze.py'), 'Script /home/user/analyze.py is missing.'


def test_analyze_execution_and_accuracy():
    script_path = '/home/user/analyze.py'
    results_path = '/home/user/results.json'

    # Add verification-only routes after the agent has finished. This ensures the
    # script and API process the live graph rather than embedding known records.
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DELETE FROM routes WHERE source='VERIFY_HUB' OR destination='VERIFY_HUB' OR destination='STORE_VERIFY'")
    conn.executemany(
        'INSERT INTO routes(source, destination, cost) VALUES (?, ?, ?)',
        [
            ('WH_ALPHA', 'VERIFY_HUB', 3.0),
            ('VERIFY_HUB', 'STORE_VERIFY', 4.25),
            ('VERIFY_HUB', 'STORE_055', 2.0),
        ],
    )
    conn.commit()
    conn.close()

    expected = expected_results_from_routes()
    assert any(item['destination'] == 'STORE_VERIFY' for item in expected)

    # Exercise the restarted Query API against answers independently derived from
    # the routes table.
    for item in expected:
        query = urllib.parse.urlencode({
            'source': 'WH_ALPHA',
            'destination': item['destination'],
        })
        try:
            with urllib.request.urlopen(
                'http://127.0.0.1:5001/shortest_path?' + query, timeout=2.0
            ) as response:
                assert response.status == 200
                payload = json.loads(response.read().decode('utf-8'))
        except Exception as exc:
            pytest.fail(f'Query API request failed for {item["destination"]}: {exc}')

        values = numeric_values(payload)
        assert any(
            math.isclose(value, item['total_cost'], rel_tol=1e-9, abs_tol=1e-9)
            for value in values
        ), f'Query API did not return the live shortest-path cost for {item["destination"]}.'

    if os.path.exists(results_path):
        os.remove(results_path)

    start_time = time.time()
    try:
        subprocess.run(
            ['python3', script_path], check=True, capture_output=True, text=True,
            timeout=2.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'Execution of {script_path} exceeds the 2.0s threshold.')
    except subprocess.CalledProcessError as exc:
        pytest.fail(f'Execution of {script_path} failed with error:\n{exc.stderr}')
    elapsed = time.time() - start_time

    assert elapsed <= 2.0, f'Execution time {elapsed:.3f}s exceeds the 2.0s threshold.'
    assert os.path.isfile(results_path), f'Output file {results_path} was not created.'

    with open(results_path, 'r') as handle:
        try:
            agent_data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f'Output file {results_path} is not valid JSON.')

    assert agent_data == expected, 'Accuracy must be 1.0. The generated results do not match the live route graph.'


def test_query_api_modified():
    app_path = '/app/query_api/app.py'
    assert os.path.isfile(app_path), f'{app_path} is missing.'

    with open(app_path, 'r') as handle:
        content = handle.read()

    # Preserve the original source assertions in addition to behavioral testing.
    assert 'routes_cache' not in content or 'SELECT * FROM routes_cache' not in content, 'Query API still appears to use the stale routes_cache.'
    assert 'RECURSIVE' in content.upper(), 'Query API does not appear to use a RECURSIVE CTE as required.'


def test_routes_traversal_index_exists():
    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute("PRAGMA index_list('routes')").fetchall()
    indexed_columns = []
    for index in indexes:
        name = index[1]
        columns = [row[2] for row in conn.execute(f"PRAGMA index_info('{name}')").fetchall()]
        indexed_columns.append(columns)
    conn.close()

    assert any(columns and columns[0] == 'source' for columns in indexed_columns), \
        'The routes table lacks an index beginning with source for recursive traversal.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
