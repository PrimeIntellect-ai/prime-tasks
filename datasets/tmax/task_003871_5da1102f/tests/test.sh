#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
import random
import subprocess
import time

import pandas as pd
import pytest

AGENT_BIN = '/home/user/fast_query'
AGENT_SRC = '/home/user/fast_query.go'
BUILT_BIN = '/tmp/fast_query_from_source'
NODES = '/app/data/nodes.jsonl'
EDGES = '/app/data/edges.jsonl'
APP_RESULTS = '/app/data/results.csv'
AGENT_RESULTS = '/home/user/results.csv'


def remove_if_present(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def run_and_time(cmd, cwd):
    remove_if_present(os.path.join(cwd, 'results.csv'))
    start = time.perf_counter()
    try:
        subprocess.run(cmd, check=True, cwd=cwd,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Command {cmd} failed in {cwd}: {e}')
    return time.perf_counter() - start


def build_source():
    remove_if_present(BUILT_BIN)
    try:
        subprocess.run(['go', 'build', '-o', BUILT_BIN, AGENT_SRC], check=True,
                       cwd='/home/user', stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'fast_query.go did not compile:\n{e.stderr}')
    assert os.path.isfile(BUILT_BIN)
    assert os.access(BUILT_BIN, os.X_OK)


def file_hash(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def expected_csv(edges):
    knows = set()
    purchases = {}
    for edge in edges:
        if edge['rel'] == 'KNOWS' and edge['src'] != edge['dst']:
            knows.add(tuple(sorted((edge['src'], edge['dst']))))
        elif edge['rel'] == 'BOUGHT':
            purchases.setdefault(edge['dst'], set()).add(edge['src'])

    rows = set()
    for product, users in purchases.items():
        ordered = sorted(users)
        for i, u1 in enumerate(ordered):
            for u2 in ordered[i + 1:]:
                if (u1, u2) in knows:
                    rows.add((u1, u2, product))

    out = io.StringIO(newline='')
    writer = csv.writer(out, lineterminator='\n')
    writer.writerow(['User1', 'User2', 'Product'])
    for row in sorted(rows, key=lambda r: (r[2], r[0], r[1])):
        writer.writerow(row)
    return out.getvalue().encode()


def write_dataset(nodes, edges):
    with open(NODES, 'w') as f:
        for node in nodes:
            f.write(json.dumps(node) + '\n')
    with open(EDGES, 'w') as f:
        for edge in edges:
            f.write(json.dumps(edge) + '\n')


def run_and_check(executable, expected):
    remove_if_present(APP_RESULTS)
    remove_if_present(AGENT_RESULTS)
    before_nodes = file_hash(NODES)
    before_edges = file_hash(EDGES)
    try:
        subprocess.run([executable], cwd='/home/user', check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'{executable} failed on a verifier-generated dataset: {e}')
    assert file_hash(NODES) == before_nodes, 'Program modified nodes.jsonl'
    assert file_hash(EDGES) == before_edges, 'Program modified edges.jsonl'
    assert os.path.isfile(AGENT_RESULTS), 'Program did not create /home/user/results.csv'
    with open(AGENT_RESULTS, 'rb') as f:
        actual = f.read()
    assert actual == expected, 'Output was incorrect or not in the required deterministic CSV order'


def test_agent_artifacts_exist_and_are_go():
    assert os.path.isfile(AGENT_BIN), f'Agent binary {AGENT_BIN} does not exist.'
    assert os.access(AGENT_BIN, os.X_OK), f'Agent binary {AGENT_BIN} is not executable.'
    assert os.path.isfile(AGENT_SRC), f'Required Go source {AGENT_SRC} does not exist.'
    assert os.path.getsize(AGENT_SRC) > 0, f'Required Go source {AGENT_SRC} is empty.'

    info = subprocess.run(['go', 'version', '-m', AGENT_BIN], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert info.returncode == 0 and 'go1.' in (info.stdout + info.stderr), \
        'fast_query must be a compiled Go executable.'
    build_source()


def test_correctness_on_provided_dataset():
    ref_cmd = ['/app/ref_engine']
    agent_cmd = [AGENT_BIN]

    remove_if_present(APP_RESULTS)
    try:
        subprocess.run(ref_cmd, cwd='/app/data', check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        pytest.fail('Reference engine failed to run.')

    assert os.path.exists(APP_RESULTS), 'Reference engine did not produce results.csv'
    ref_df = pd.read_csv(APP_RESULTS)

    # The reference output must not be available when the submitted program runs.
    remove_if_present(APP_RESULTS)
    remove_if_present(AGENT_RESULTS)
    nodes_hash = file_hash(NODES)
    edges_hash = file_hash(EDGES)
    try:
        subprocess.run(agent_cmd, cwd='/home/user', check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        pytest.fail('Agent fast_query failed to run.')

    assert file_hash(NODES) == nodes_hash, 'Agent modified nodes.jsonl'
    assert file_hash(EDGES) == edges_hash, 'Agent modified edges.jsonl'
    assert os.path.exists(AGENT_RESULTS), f'Agent did not produce {AGENT_RESULTS}'
    agent_df = pd.read_csv(AGENT_RESULTS)

    ref_sorted = ref_df.sort_values(by=['Product', 'User1', 'User2']).reset_index(drop=True)
    agent_sorted = agent_df.sort_values(by=['Product', 'User1', 'User2']).reset_index(drop=True)
    try:
        pd.testing.assert_frame_equal(ref_sorted, agent_sorted)
    except AssertionError as e:
        pytest.fail(f'Agent results.csv does not match reference output:\n{e}')


def test_generated_dataset_and_rebuilt_source():
    build_source()
    original_nodes = open(NODES, 'rb').read()
    original_edges = open(EDGES, 'rb').read()

    users = [f'TU{i:03d}' for i in range(120)]
    products = [f'TP{i:02d}' for i in range(13)]
    nodes = ([{'id': u, 'type': 'User'} for u in users] +
             [{'id': p, 'type': 'Product'} for p in products])
    rng = random.Random(917263)
    edges = [
        {'src': 'TU002', 'dst': 'TU001', 'rel': 'KNOWS'},
        {'src': 'TU002', 'dst': 'TU003', 'rel': 'KNOWS'},
        {'src': 'TU001', 'dst': 'TP00', 'rel': 'BOUGHT'},
        {'src': 'TU002', 'dst': 'TP00', 'rel': 'BOUGHT'},
        {'src': 'TU002', 'dst': 'TP00', 'rel': 'BOUGHT'},
        {'src': 'TU003', 'dst': 'TP00', 'rel': 'BOUGHT'},
    ]
    for _ in range(500):
        a, b = rng.sample(users, 2)
        edges.append({'src': a, 'dst': b, 'rel': 'KNOWS'})
    for _ in range(600):
        edges.append({'src': rng.choice(users), 'dst': rng.choice(products), 'rel': 'BOUGHT'})

    try:
        write_dataset(nodes, edges)
        expected = expected_csv(edges)
        run_and_check(AGENT_BIN, expected)
        run_and_check(BUILT_BIN, expected)
    finally:
        with open(NODES, 'wb') as f:
            f.write(original_nodes)
        with open(EDGES, 'wb') as f:
            f.write(original_edges)
        remove_if_present(APP_RESULTS)
        remove_if_present(AGENT_RESULTS)


def test_speedup():
    build_source()
    ref_cmd = ['/app/ref_engine']
    agent_cmd = [AGENT_BIN]
    built_cmd = [BUILT_BIN]

    # Preserve the original speed assertion for the submitted executable.
    t_ref = sum(run_and_time(ref_cmd, cwd='/app/data') for _ in range(3)) / 3.0
    remove_if_present(APP_RESULTS)
    t_agent = sum(run_and_time(agent_cmd, cwd='/home/user') for _ in range(3)) / 3.0
    remove_if_present(APP_RESULTS)
    t_built = sum(run_and_time(built_cmd, cwd='/home/user') for _ in range(3)) / 3.0

    speedup = t_ref / t_agent
    source_speedup = t_ref / t_built
    assert speedup >= 10.0, (
        f'Speedup is {speedup:.2f}x, which is less than the required 10.0x threshold. '
        f'(Reference time: {t_ref:.4f}s, Agent time: {t_agent:.4f}s)'
    )
    assert source_speedup >= 10.0, (
        f'The executable rebuilt from fast_query.go is only {source_speedup:.2f}x faster '
        f'than the reference. (Reference time: {t_ref:.4f}s, rebuilt time: {t_built:.4f}s)'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
