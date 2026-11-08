#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'ORACLE_EOF' > /tmp/correct_path_oracle.py
import csv
import json
import math
import sys

csv_file, queries_file, output_file = sys.argv[1:4]

aggregated = {}
with open(csv_file, newline='') as f:
    for row in csv.DictReader(f):
        try:
            amount = float(row['amount'])
        except (ValueError, TypeError):
            continue
        if row['status'] != 'completed' or amount < 100:
            continue
        key = (row['src_account'], row['dst_account'])
        aggregated[key] = aggregated.get(key, 0.0) + amount

# Deliberately retain the reference implementation's unoptimized behavior:
# every relaxation scans the complete edge list.
edges = sorted((src, dst, 1.0 / amount) for (src, dst), amount in aggregated.items())
nodes = sorted({x for edge in edges for x in edge[:2]})
node_set = set(nodes)

with open(queries_file) as f:
    queries = json.load(f)

results = []
for query in queries:
    src = query['src']
    dst = query['dst']
    if src == dst:
        results.append({'src': src, 'dst': dst, 'path': [src], 'total_weight': 0.0})
        continue
    if src not in node_set or dst not in node_set:
        continue

    dist = {node: math.inf for node in nodes}
    prev = {}
    visited = set()
    dist[src] = 0.0

    while len(visited) < len(nodes):
        candidates = [node for node in nodes if node not in visited]
        if not candidates:
            break
        current = min(candidates, key=lambda node: (dist[node], node))
        if math.isinf(dist[current]):
            break
        visited.add(current)
        if current == dst:
            break

        for edge_src, edge_dst, weight in edges:
            if edge_src != current or edge_dst in visited:
                continue
            candidate = dist[current] + weight
            if candidate < dist[edge_dst]:
                dist[edge_dst] = candidate
                prev[edge_dst] = current

    if math.isinf(dist[dst]):
        continue
    path = [dst]
    while path[-1] != src:
        if path[-1] not in prev:
            path = []
            break
        path.append(prev[path[-1]])
    if not path:
        continue
    path.reverse()
    if len(path) - 1 > 6:
        continue
    results.append({
        'src': src,
        'dst': dst,
        'path': path,
        'total_weight': dist[dst],
    })

results.sort(key=lambda item: (item['total_weight'], item['src'], item['dst']))
with open(output_file, 'w') as f:
    json.dump(results[:50], f, separators=(',', ':'))
ORACLE_EOF
chmod 755 /tmp/correct_path_oracle.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import time
import pytest

AGENT_FILE = '/home/user/processor.go'
OUTPUT_FILE = '/home/user/output.json'
CSV_FILE = '/home/user/transactions.csv'
QUERIES_FILE = '/home/user/queries.json'
ORACLE_OUT = '/tmp/oracle_out.json'


def test_processor_go_exists():
    assert os.path.isfile(AGENT_FILE), 'Missing file: /home/user/processor.go'
    build = subprocess.run(
        ['go', 'build', '-o', '/tmp/processor_verify', AGENT_FILE],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f'processor.go does not compile:\n{build.stdout}\n{build.stderr}'
    assert os.path.isfile('/tmp/processor_verify') and os.access('/tmp/processor_verify', os.X_OK)


def test_output_and_speedup():
    csv_backup = '/tmp/transactions.csv.verifier-backup'
    queries_backup = '/tmp/queries.json.verifier-backup'
    shutil.copy2(CSV_FILE, csv_backup)
    shutil.copy2(QUERIES_FILE, queries_backup)

    # Add an unpredictable high-liquidity component. It leaves the workload size
    # essentially unchanged but prevents a precomputed or fabricated output from passing.
    nonce = secrets.token_hex(12)
    src = 'VERIFY_SRC_' + nonce
    mid = 'VERIFY_MID_' + nonce
    dst = 'VERIFY_DST_' + nonce
    try:
        with open(CSV_FILE, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['VERIFY1_' + nonce, src, mid, 1000000000000, 'completed', '2023-01-01T00:00:00Z'])
            writer.writerow(['VERIFY2_' + nonce, src, mid, 2000000000000, 'completed', '2023-01-01T00:00:00Z'])
            writer.writerow(['VERIFY3_' + nonce, mid, dst, 4000000000000, 'completed', '2023-01-01T00:00:00Z'])
            writer.writerow(['VERIFY4_' + nonce, src, dst, 9000000000000000, 'pending', '2023-01-01T00:00:00Z'])
            writer.writerow(['VERIFY5_' + nonce, src, dst, 50, 'completed', '2023-01-01T00:00:00Z'])

        with open(QUERIES_FILE) as f:
            queries = json.load(f)
        queries.append({'src': src, 'dst': dst})
        with open(QUERIES_FILE, 'w') as f:
            json.dump(queries, f)

        for path in (OUTPUT_FILE, ORACLE_OUT):
            if os.path.exists(path):
                os.remove(path)

        start_agent = time.monotonic()
        agent = subprocess.run(
            ['go', 'run', AGENT_FILE],
            capture_output=True,
            text=True,
            timeout=240,
        )
        agent_time = time.monotonic() - start_agent
        assert agent.returncode == 0, (
            'Agent program failed to execute:\n'
            f'STDOUT:\n{agent.stdout}\nSTDERR:\n{agent.stderr}'
        )
        assert os.path.isfile(OUTPUT_FILE), f'Agent program did not produce {OUTPUT_FILE}'
        try:
            with open(OUTPUT_FILE) as f:
                agent_output = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'Could not parse {OUTPUT_FILE} as valid JSON: {exc}')

        start_oracle = time.monotonic()
        oracle = subprocess.run(
            ['python3', '/tmp/correct_path_oracle.py', CSV_FILE, QUERIES_FILE, ORACLE_OUT],
            capture_output=True,
            text=True,
            timeout=240,
        )
        oracle_time = time.monotonic() - start_oracle
        assert oracle.returncode == 0, (
            'Reference program failed to execute:\n'
            f'STDOUT:\n{oracle.stdout}\nSTDERR:\n{oracle.stderr}'
        )
        assert os.path.isfile(ORACLE_OUT), f'Reference program did not produce {ORACLE_OUT}'
        with open(ORACLE_OUT) as f:
            oracle_output = json.load(f)

        assert agent_output == oracle_output, (
            'Outputs do not match exactly! The Top 50 paths or their order differ from the reference.'
        )

        speedup = oracle_time / agent_time
        assert speedup >= 4.0, (
            f'Speedup {speedup:.2f} is below the 4.0x threshold. '
            f'(Oracle: {oracle_time:.2f}s, Agent: {agent_time:.2f}s)'
        )
    finally:
        shutil.move(csv_backup, CSV_FILE)
        shutil.move(queries_backup, QUERIES_FILE)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
