#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import sys
from collections import defaultdict, deque

import pytest
from pymongo import MongoClient

RAW = '/home/user/raw_transactions.json'
AGGREGATE = '/home/user/aggregate.js'
EDGES = '/home/user/filtered_edges.json'
SHORTEST = '/home/user/shortest_path.py'
SOLUTION = '/home/user/solution.json'


def run(cmd):
    return subprocess.run(cmd, cwd='/home/user', text=True, capture_output=True,
                          timeout=45, check=True)


def expected_edges(data):
    totals = defaultdict(int)
    for tx in data:
        if tx.get('amount', 0) >= 1000:
            totals[(tx['from_acct'], tx['to_acct'])] += tx['amount']
    return [
        {'from_acct': pair[0], 'to_acct': pair[1], 'total_volume': total}
        for pair, total in sorted(totals.items(), key=lambda item: item[1], reverse=True)
    ]


def compute_expected_solution(raw_data_path):
    with open(raw_data_path, 'r') as f:
        data = json.load(f)

    edges = defaultdict(int)
    for tx in data:
        if tx.get('amount', 0) >= 1000:
            edge = (tx['from_acct'], tx['to_acct'])
            edges[edge] += tx['amount']

    if not edges:
        return None

    top_edge = max(edges.items(), key=lambda x: x[1])
    top_edge_dict = {
        'from_acct': top_edge[0][0],
        'to_acct': top_edge[0][1],
        'total_volume': top_edge[1]
    }

    graph = defaultdict(list)
    for (u, v) in edges.keys():
        graph[u].append(v)

    queue = deque([['ACCT_START']])
    visited = {'ACCT_START'}
    shortest_path = None
    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == 'ACCT_TARGET':
            shortest_path = path
            break
        for neighbor in graph[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    if not shortest_path:
        return None

    volume = sum(edges[(shortest_path[i], shortest_path[i + 1])]
                 for i in range(len(shortest_path) - 1))
    return {
        'path': shortest_path,
        'path_volume_sum': volume,
        'top_edge_overall': top_edge_dict
    }


def load_json(path):
    with open(path, 'r') as f:
        return json.load(f)


def assert_edges(actual, expected):
    assert isinstance(actual, list), 'filtered_edges.json must contain a JSON array.'
    assert actual == expected, f'Unexpected aggregated edges: {actual}'
    assert all(set(edge) == {'from_acct', 'to_acct', 'total_volume'} for edge in actual)
    assert all(actual[i]['total_volume'] >= actual[i + 1]['total_volume']
               for i in range(len(actual) - 1)), 'Edges are not sorted descending.'


def assert_solution(actual, expected):
    assert set(actual) == {'path', 'path_volume_sum', 'top_edge_overall'}
    assert actual['path'] == expected['path']
    assert actual['path_volume_sum'] == expected['path_volume_sum']
    assert actual['top_edge_overall'] == expected['top_edge_overall']


def test_artifacts_database_and_initial_execution():
    for path in (AGGREGATE, SHORTEST):
        assert os.path.exists(path), f'{path} is missing.'
        assert os.path.isfile(path), f'{path} is not a regular file.'
        assert os.path.getsize(path) > 0, f'{path} is empty.'

    assert shutil.which('mongod'), 'MongoDB server is not installed.'
    subprocess.run(['mongod', '--version'], check=True, capture_output=True, timeout=10)

    client = MongoClient('mongodb://127.0.0.1:27017', serverSelectionTimeoutMS=3000)
    assert client.admin.command('ping')['ok'] == 1, 'MongoDB is not running on the default port.'

    raw = load_json(RAW)
    stored = list(client.fraud_db.transactions.find({}, {'_id': 0}))
    assert stored == raw, 'fraud_db.transactions was not populated from raw_transactions.json.'

    node_source = open(AGGREGATE, 'r').read()
    py_source = open(SHORTEST, 'r').read()
    assert re.search(r"['\"]mongodb['\"]", node_source), 'aggregate.js does not use the official mongodb package.'
    assert re.search(r'\.aggregate\s*\(', node_source), 'aggregate.js does not run an aggregation pipeline.'
    assert re.search(r'(^|\n)\s*(import\s+(networkx|igraph|rustworkx)|from\s+(networkx|igraph|rustworkx)\s+import)', py_source), 'shortest_path.py does not import a graph library.'

    run(['node', '--check', AGGREGATE])
    run([sys.executable, '-m', 'py_compile', SHORTEST])
    for path in (EDGES, SOLUTION):
        if os.path.exists(path):
            os.remove(path)
    run(['node', AGGREGATE])
    assert os.path.isfile(EDGES), 'aggregate.js did not create filtered_edges.json.'
    assert_edges(load_json(EDGES), expected_edges(raw))
    run([sys.executable, SHORTEST])
    assert os.path.isfile(SOLUTION), 'shortest_path.py did not create solution.json.'


def test_solution_file_exists():
    assert os.path.exists(SOLUTION), 'The file /home/user/solution.json is missing.'
    assert os.path.isfile(SOLUTION), '/home/user/solution.json is not a file.'


def test_solution_content():
    assert os.path.exists(RAW), f'Raw transactions file missing at {RAW}.'
    expected = compute_expected_solution(RAW)
    assert expected is not None, 'Could not compute expected solution from raw data.'
    try:
        solution = load_json(SOLUTION)
    except json.JSONDecodeError:
        pytest.fail('/home/user/solution.json does not contain valid JSON.')

    assert 'path' in solution, "Missing 'path' in solution.json"
    assert solution['path'] == expected['path'], f"Expected path {expected['path']}, got {solution['path']}"
    assert 'path_volume_sum' in solution, "Missing 'path_volume_sum' in solution.json"
    assert solution['path_volume_sum'] == expected['path_volume_sum']
    assert 'top_edge_overall' in solution, "Missing 'top_edge_overall' in solution.json"
    top_edge = solution['top_edge_overall']
    expected_top = expected['top_edge_overall']
    assert top_edge.get('from_acct') == expected_top['from_acct']
    assert top_edge.get('to_acct') == expected_top['to_acct']
    assert top_edge.get('total_volume') == expected_top['total_volume']


def test_pipeline_on_unseen_database_data():
    client = MongoClient('mongodb://127.0.0.1:27017', serverSelectionTimeoutMS=3000)
    db = client.fraud_db
    collection = db.transactions
    original_raw_text = open(RAW, 'r').read()
    original_docs = list(collection.find({}, {'_id': 0}))
    suffix = secrets.token_hex(5)
    p, q, r = 'P_' + suffix, 'Q_' + suffix, 'R_' + suffix
    x, y = 'X_' + suffix, 'Y_' + suffix
    bump = random.SystemRandom().randint(17, 401)
    fixture = [
        {'tx_id': 'u1_' + suffix, 'from_acct': 'ACCT_START', 'to_acct': p, 'amount': 1000 + bump},
        {'tx_id': 'u2_' + suffix, 'from_acct': 'ACCT_START', 'to_acct': p, 'amount': 700},
        {'tx_id': 'u3_' + suffix, 'from_acct': p, 'to_acct': 'ACCT_TARGET', 'amount': 4100 + bump},
        {'tx_id': 'u4_' + suffix, 'from_acct': 'ACCT_START', 'to_acct': q, 'amount': 2500 + bump},
        {'tx_id': 'u5_' + suffix, 'from_acct': q, 'to_acct': r, 'amount': 2600 + bump},
        {'tx_id': 'u6_' + suffix, 'from_acct': r, 'to_acct': 'ACCT_TARGET', 'amount': 2700 + bump},
        {'tx_id': 'u7_' + suffix, 'from_acct': 'ACCT_START', 'to_acct': 'ACCT_TARGET', 'amount': 999},
        {'tx_id': 'u8_' + suffix, 'from_acct': x, 'to_acct': y, 'amount': 12000 + bump},
        {'tx_id': 'u9_' + suffix, 'from_acct': x, 'to_acct': y, 'amount': 1800 + bump}
    ]
    expected_agg = expected_edges(fixture)
    expected = {
        'path': ['ACCT_START', p, 'ACCT_TARGET'],
        'path_volume_sum': (1000 + bump) + (4100 + bump),
        'top_edge_overall': {'from_acct': x, 'to_acct': y, 'total_volume': 13800 + 2 * bump}
    }

    try:
        collection.delete_many({})
        collection.insert_many(fixture)
        with open(RAW, 'w') as f:
            json.dump([{'tx_id': 'decoy', 'from_acct': 'ACCT_START', 'to_acct': 'ACCT_TARGET', 'amount': 999999}], f)

        db.command('profile', 0)
        db['system.profile'].drop()
        db.command('profile', 2)
        if os.path.exists(EDGES):
            os.remove(EDGES)
        run(['node', AGGREGATE])
        profile_hits = list(db['system.profile'].find({'command.aggregate': 'transactions'}))
        db.command('profile', 0)
        assert profile_hits, 'aggregate.js did not issue a MongoDB aggregate command on transactions.'
        assert_edges(load_json(EDGES), expected_agg)

        # The Python phase must consume filtered_edges.json, not reconstruct from MongoDB.
        collection.delete_many({})
        collection.insert_one({'tx_id': 'db_decoy', 'from_acct': 'ACCT_START', 'to_acct': 'ACCT_TARGET', 'amount': 500000})
        if os.path.exists(SOLUTION):
            os.remove(SOLUTION)
        run([sys.executable, SHORTEST])
        assert_solution(load_json(SOLUTION), expected)
    finally:
        try:
            db.command('profile', 0)
        except Exception:
            pass
        with open(RAW, 'w') as f:
            f.write(original_raw_text)
        collection.delete_many({})
        if original_docs:
            collection.insert_many(original_docs)
        try:
            run(['node', AGGREGATE])
            run([sys.executable, SHORTEST])
        except Exception:
            pass
        client.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
