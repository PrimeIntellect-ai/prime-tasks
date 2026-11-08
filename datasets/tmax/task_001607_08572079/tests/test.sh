#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
from collections import deque

import pytest

SOURCE = '/home/user/path_finder.c'
EXECUTABLE = '/home/user/path_finder'
DATABASE = '/home/user/knowledge.db'
OUTPUT = '/home/user/path.txt'
REBUILT = '/tmp/path_finder_verified'
ORIGINAL_EXPECTED = ['Alpha', 'Beta', 'Zeta', 'Omega']


def read_output():
    assert os.path.exists(OUTPUT), f'The file {OUTPUT} does not exist.'
    assert os.path.isfile(OUTPUT), f'{OUTPUT} is not a file.'
    with open(OUTPUT, 'r') as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def run_candidate(executable, start, destination, expected):
    if os.path.lexists(OUTPUT):
        assert not os.path.isdir(OUTPUT), f'{OUTPUT} must not be a directory.'
        os.unlink(OUTPUT)

    try:
        result = subprocess.run(
            [executable, start, destination],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'{executable} timed out for {start!r} -> {destination!r}.')

    assert result.returncode == 0, (
        f'{executable} failed for {start!r} -> {destination!r} with exit code '
        f'{result.returncode}. stderr: {result.stderr}'
    )
    actual = read_output()
    assert actual == expected, (
        f'For {start!r} -> {destination!r}, expected {expected}, but got {actual}.'
    )


def shortest_path(names, edges, start, destination):
    adjacency = {name: [] for name in names}
    for src, dst in edges:
        adjacency[src].append(dst)
    for neighbors in adjacency.values():
        neighbors.sort()

    queue = deque([start])
    previous = {start: None}
    while queue:
        current = queue.popleft()
        if current == destination:
            break
        for neighbor in adjacency[current]:
            if neighbor not in previous:
                previous[neighbor] = current
                queue.append(neighbor)

    assert destination in previous
    path = []
    current = destination
    while current is not None:
        path.append(current)
        current = previous[current]
    return list(reversed(path))


def install_dynamic_database():
    token = secrets.token_hex(8)
    names = [
        f'Start_{token}', f'A_branch_{token}', f'B_branch_{token}',
        f'X_step_{token}', f'Y_step_{token}', f'Goal_{token}',
        f'ShortStart_{token}', f'A_long_{token}', f'B_short_{token}',
        f'P_long_{token}', f'Q_long_{token}', f'ShortGoal_{token}',
    ]
    names.extend(f'N_{secrets.token_hex(6)}' for _ in range(9))

    s, a, b, x, y, g, t, low, high, p, q, g2 = names[:12]
    cycle = names[12:]
    edges = [
        (s, b), (s, a), (a, x), (b, y), (x, g), (y, g),
        (t, low), (low, p), (p, q), (q, g2), (t, high), (high, g2),
    ]
    for index, node in enumerate(cycle):
        edges.append((node, cycle[(index + 1) % len(cycle)]))
    edges.extend([
        (cycle[0], cycle[3]),
        (cycle[0], cycle[4]),
        (cycle[3], cycle[7]),
        (cycle[4], cycle[7]),
        (cycle[7], cycle[1]),
    ])

    rng = random.SystemRandom()
    ids = list(range(101, 101 + len(names)))
    rng.shuffle(ids)
    name_to_id = dict(zip(names, ids))
    node_rows = list(zip(ids, names))
    edge_rows = [(name_to_id[src], name_to_id[dst]) for src, dst in edges]
    rng.shuffle(node_rows)
    rng.shuffle(edge_rows)

    temporary = DATABASE + '.verifier-new'
    if os.path.exists(temporary):
        os.unlink(temporary)
    connection = sqlite3.connect(temporary)
    try:
        connection.execute('CREATE TABLE _node_data (node_id INTEGER PRIMARY KEY, node_name TEXT)')
        connection.execute('CREATE TABLE _edge_data (src INTEGER, dst INTEGER)')
        connection.executemany('INSERT INTO _node_data VALUES (?, ?)', node_rows)
        connection.executemany('INSERT INTO _edge_data VALUES (?, ?)', edge_rows)
        connection.commit()
    finally:
        connection.close()
    os.replace(temporary, DATABASE)

    queries = [(s, g), (t, g2), (cycle[0], cycle[1]), (cycle[5], cycle[3])]
    return [(start, destination, shortest_path(names, edges, start, destination))
            for start, destination in queries]


def test_c_source_code():
    assert os.path.exists(SOURCE), f'The C source file {SOURCE} does not exist.'

    with open(SOURCE, 'r') as f:
        content = f.read()

    assert '#include <sqlite3.h>' in content or '#include<sqlite3.h>' in content or '#include "sqlite3.h"' in content, \
        f'The file {SOURCE} must include sqlite3.h.'

    assert 'sqlite3_bind_' in content, \
        f'The file {SOURCE} must use parameterized queries (sqlite3_bind_* functions).'


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f'The executable {EXECUTABLE} does not exist.'
    assert os.path.isfile(EXECUTABLE), f'{EXECUTABLE} is not a file.'
    assert os.access(EXECUTABLE, os.X_OK), f'The file {EXECUTABLE} is not executable.'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXECUTABLE} must be a compiled executable.'


def test_program_behavior_and_source_build():
    compile_result = subprocess.run(
        ['gcc', SOURCE, '-o', REBUILT, '-lsqlite3'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f'{SOURCE} could not be compiled with SQLite: {compile_result.stderr}'
    )

    with open(DATABASE, 'rb') as f:
        original_database = f.read()

    try:
        run_candidate(EXECUTABLE, 'Alpha', 'Omega', ORIGINAL_EXPECTED)
        run_candidate(REBUILT, 'Alpha', 'Omega', ORIGINAL_EXPECTED)

        dynamic_queries = install_dynamic_database()
        for executable in (EXECUTABLE, REBUILT):
            for start, destination, expected in dynamic_queries:
                run_candidate(executable, start, destination, expected)
    finally:
        restore_path = DATABASE + '.verifier-restore'
        with open(restore_path, 'wb') as f:
            f.write(original_database)
        os.replace(restore_path, DATABASE)
        subprocess.run(
            [EXECUTABLE, 'Alpha', 'Omega'],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )


def test_path_txt_content():
    path_txt = '/home/user/path.txt'
    assert os.path.exists(path_txt), f'The file {path_txt} does not exist.'
    assert os.path.isfile(path_txt), f'{path_txt} is not a file.'

    expected_lines = ['Alpha', 'Beta', 'Zeta', 'Omega']

    with open(path_txt, 'r') as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]

    assert content == expected_lines, f'Expected path {expected_lines}, but got {content} in {path_txt}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
