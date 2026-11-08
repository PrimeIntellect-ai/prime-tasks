#!/bin/bash
set -e
mkdir -p /logs/verifier

verify() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import heapq
import pytest

def compute_expected_summary():
    nodes = {}
    with open('/home/user/nodes.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[row['id']] = int(row['cost'])

    edges = {}
    with open('/home/user/edges.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src = row['src']
            dst = row['dst']
            weight = int(row['weight'])
            edges.setdefault(src, []).append((dst, weight))

    distances = {'ROOT': 0}
    pq = [(0, 'ROOT')]
    while pq:
        dist, current = heapq.heappop(pq)
        if dist > distances.get(current, float('inf')):
            continue
        for neighbor, weight in edges.get(current, []):
            new_dist = dist + weight
            if new_dist < distances.get(neighbor, float('inf')):
                distances[neighbor] = new_dist
                heapq.heappush(pq, (new_dist, neighbor))

    reachable = []
    for node, dist in distances.items():
        reachable.append({'id': node, 'distance': dist, 'cost': nodes[node]})
    reachable.sort(key=lambda x: (x['distance'], x['id']))

    cumulative_cost = 0
    for node in reachable:
        cumulative_cost += node['cost']
        node['cumulative_cost'] = cumulative_cost

    distance_groups = {}
    for node in reachable:
        distance_groups.setdefault(node['distance'], []).append(node)

    for group in distance_groups.values():
        group_sorted = sorted(group, key=lambda x: x['cost'], reverse=True)
        ranks = {}
        rank = 1
        for j, node in enumerate(group_sorted):
            if j > 0 and node['cost'] < group_sorted[j - 1]['cost']:
                rank = j + 1
            ranks[node['id']] = rank
        for node in group:
            node['cost_rank'] = ranks[node['id']]

    return reachable

def test_summary_json_exists():
    assert os.path.isfile('/home/user/summary.json'), '/home/user/summary.json is missing. The Go program did not produce the expected output file.'

def test_summary_json_content():
    expected_data = compute_expected_summary()
    with open('/home/user/summary.json', 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('/home/user/summary.json is not a valid JSON file.')

    assert isinstance(actual_data, list), 'The JSON output should be an array of objects.'
    assert len(actual_data) == len(expected_data), f'Expected {len(expected_data)} reachable nodes, but got {len(actual_data)}.'
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get('id') == expected['id'], f"Record {i}: Expected id '{expected['id']}', got '{actual.get('id')}'"
        assert actual.get('distance') == expected['distance'], f"Record {i} ({expected['id']}): Expected distance {expected['distance']}, got {actual.get('distance')}"
        assert actual.get('cost') == expected['cost'], f"Record {i} ({expected['id']}): Expected cost {expected['cost']}, got {actual.get('cost')}"
        assert actual.get('cumulative_cost') == expected['cumulative_cost'], f"Record {i} ({expected['id']}): Expected cumulative_cost {expected['cumulative_cost']}, got {actual.get('cumulative_cost')}"
        assert actual.get('cost_rank') == expected['cost_rank'], f"Record {i} ({expected['id']}): Expected cost_rank {expected['cost_rank']}, got {actual.get('cost_rank')}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    test -d /home/user/etl_pipeline || return 1
    test -f /home/user/etl_pipeline/main.go || return 1
    test -f /home/user/etl_pipeline/go.mod || return 1

    python3 - << 'PY' || return 1
import glob
import re

paths = glob.glob('/home/user/etl_pipeline/*.go')
assert '/home/user/etl_pipeline/main.go' in paths
source = '\n'.join(open(path, encoding='utf-8').read() for path in paths)
source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
source = re.sub(r'(?m)^\s*//.*$', '', source)
assert re.search(r'\bpackage\s+main\b', source)
assert re.search(r'["`]database/sql["`]', source), 'Go program must use database/sql'
assert re.search(r'(?i)sqlite', source), 'Go program must use a SQLite driver'
assert re.search(r'(?is)SUM\s*\([^)]*\)\s*OVER\s*\(', source), 'SQL SUM window query is missing'
assert re.search(r'(?is)RANK\s*\(\s*\)\s*OVER\s*\(', source), 'SQL RANK window query is missing'
PY

    (cd /home/user/etl_pipeline && go build -o /tmp/etl_pipeline_submission .) || return 1
    test -x /tmp/etl_pipeline_submission || return 1

    tmpdir=$(mktemp -d)
    cp /home/user/nodes.csv "$tmpdir/nodes.csv"
    cp /home/user/edges.csv "$tmpdir/edges.csv"
    cp /home/user/summary.json "$tmpdir/summary.json"

    cleanup_dynamic() {
        cp "$tmpdir/nodes.csv" /home/user/nodes.csv
        cp "$tmpdir/edges.csv" /home/user/edges.csv
        cp "$tmpdir/summary.json" /home/user/summary.json
        rm -rf "$tmpdir"
    }
    trap cleanup_dynamic RETURN

    cat << 'EOF' > /home/user/nodes.csv
id,cost
ROOT,7
X,11
Y,5
Z,13
W,17
ISOLATED,99
EOF
    cat << 'EOF' > /home/user/edges.csv
src,dst,weight
ROOT,X,2
ROOT,Y,2
X,Z,10
Y,Z,1
Z,W,1
ISOLATED,W,1
EOF
    rm -f /home/user/summary.json
    (cd /home/user/etl_pipeline && timeout 30 /tmp/etl_pipeline_submission) || return 1

    python3 - << 'PY' || return 1
import json
import os

path = '/home/user/summary.json'
assert os.path.isfile(path), 'compiled Go program did not create summary.json'
with open(path, encoding='utf-8') as f:
    actual = json.load(f)
expected = [
    {'id': 'ROOT', 'distance': 0, 'cost': 7, 'cumulative_cost': 7, 'cost_rank': 1},
    {'id': 'X', 'distance': 2, 'cost': 11, 'cumulative_cost': 18, 'cost_rank': 1},
    {'id': 'Y', 'distance': 2, 'cost': 5, 'cumulative_cost': 23, 'cost_rank': 2},
    {'id': 'Z', 'distance': 3, 'cost': 13, 'cumulative_cost': 36, 'cost_rank': 1},
    {'id': 'W', 'distance': 4, 'cost': 17, 'cumulative_cost': 53, 'cost_rank': 1},
]
assert isinstance(actual, list), 'dynamic output is not a JSON array'
assert actual == expected, f'dynamic execution produced incorrect output: {actual!r}'
PY

    cleanup_dynamic
    trap - RETURN
    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
