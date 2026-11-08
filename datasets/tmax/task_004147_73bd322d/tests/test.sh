#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess
from collections import defaultdict

SCRIPT_PATH = '/home/user/detect_deadlocks.sh'
DB_PATH = '/home/user/locks.db'
OUTPUT_PATH = '/home/user/deadlocked_txs.txt'


def read_edges(db_path=DB_PATH):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(
            'SELECT waiting_tx, blocking_tx FROM waits_for'
        ).fetchall()
    finally:
        conn.close()


def replace_edges(edges):
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('DELETE FROM waits_for')
        conn.executemany('INSERT INTO waits_for VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def get_expected_deadlocks(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('SELECT waiting_tx, blocking_tx FROM waits_for')
    edges = cursor.fetchall()
    conn.close()

    graph = defaultdict(list)
    nodes = set()
    for u, v in edges:
        graph[u].append(v)
        nodes.add(u)
        nodes.add(v)

    # Tarjan's algorithm for Strongly Connected Components (SCC)
    index = 0
    indices = {}
    lowlinks = {}
    stack = []
    on_stack = set()
    sccs = []

    def strongconnect(v):
        nonlocal index
        indices[v] = index
        lowlinks[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)

        for w in graph[v]:
            if w not in indices:
                strongconnect(w)
                lowlinks[v] = min(lowlinks[v], lowlinks[w])
            elif w in on_stack:
                lowlinks[v] = min(lowlinks[v], indices[w])

        if lowlinks[v] == indices[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == v:
                    break
            sccs.append(scc)

    for v in nodes:
        if v not in indices:
            strongconnect(v)

    deadlocked = set()
    for scc in sccs:
        if len(scc) > 1:
            deadlocked.update(scc)
        elif len(scc) == 1:
            v = scc[0]
            if v in graph[v]:
                deadlocked.add(v)

    return sorted(deadlocked)


def run_script():
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            raise AssertionError(f'Output path is a directory: {OUTPUT_PATH}')
        os.unlink(OUTPUT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'Script exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\n'
        f'stderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT_PATH), f'Output file not found at {OUTPUT_PATH}'


def assert_output(expected_deadlocks):
    assert os.path.exists(OUTPUT_PATH), f'Output file not found at {OUTPUT_PATH}'

    with open(OUTPUT_PATH, 'r') as f:
        lines = f.read().splitlines()

    actual_deadlocks = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                actual_deadlocks.append(int(line))
            except ValueError:
                assert False, f'Output file contains non-integer value: {line}'

    assert actual_deadlocks == expected_deadlocks, (
        'Deadlocked transactions do not match expected.\n'
        f'Expected: {expected_deadlocks}\n'
        f'Actual: {actual_deadlocks}'
    )


ORIGINAL_EDGES = read_edges()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'Script path is not a regular file: {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script at {SCRIPT_PATH} is not executable'


def test_script_runs_and_output_file_correctness():
    expected_deadlocks = get_expected_deadlocks(DB_PATH)
    before = sorted(read_edges())
    run_script()
    assert sorted(read_edges()) == before, 'The script must query, not modify, locks.db'
    assert_output(expected_deadlocks)


def test_script_analyzes_unseen_graphs():
    rng = random.SystemRandom()
    try:
        for cycle_length in (2, 3, 5):
            ids = rng.sample(range(10000, 9000000), cycle_length + 8)
            cycle = ids[:cycle_length]
            self_loop, tail1, tail2, dag1, dag2, dag3, sink, extra = ids[cycle_length:]

            edges = [
                (cycle[i], cycle[(i + 1) % cycle_length])
                for i in range(cycle_length)
            ]
            edges.extend([
                (self_loop, self_loop),
                (tail1, cycle[0]),
                (tail2, tail1),
                (dag1, dag2),
                (dag2, dag3),
                (dag3, sink),
                (extra, cycle[-1]),
            ])
            rng.shuffle(edges)
            replace_edges(edges)
            expected_deadlocks = get_expected_deadlocks(DB_PATH)
            before = sorted(read_edges())

            run_script()

            assert sorted(read_edges()) == before, 'The script must query, not modify, locks.db'
            assert_output(expected_deadlocks)
    finally:
        replace_edges(ORIGINAL_EDGES)
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
