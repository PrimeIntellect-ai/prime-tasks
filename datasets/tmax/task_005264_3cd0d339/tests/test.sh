#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import random
import sqlite3
import subprocess

DB_PATH = '/home/user/transactions.db'
SCRIPT_PATH = '/home/user/find_cycles.py'
LOG_PATH = '/home/user/cycles.log'
SQL_PATH = '/home/user/optimize.sql'


def create_database(edges):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE transfers (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp TEXT)')
    conn.executemany(
        'INSERT INTO transfers VALUES (?, ?, ?, ?, ?)',
        [(i, sender, receiver, 1.0, '2023-01-01')
         for i, (sender, receiver) in enumerate(edges, 1)]
    )
    conn.commit()
    conn.close()


def expected_cycles(edges):
    edge_set = set(edges)
    accounts = sorted({account for edge in edge_set for account in edge})
    found = []
    for group in itertools.combinations(accounts, 4):
        if any(
            all((order[i], order[(i + 1) % 4]) in edge_set for i in range(4))
            for order in itertools.permutations(group)
        ):
            found.append(group)
    return [','.join(map(str, group)) for group in sorted(found)]


def execute_and_read():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f'Execution of {SCRIPT_PATH} failed with error:\n{result.stderr}'
    assert os.path.isfile(LOG_PATH), f'Log file {LOG_PATH} does not exist. The script might not have created it.'
    with open(LOG_PATH, 'r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_find_cycles_script_execution():
    assert os.path.exists(SCRIPT_PATH), f'Python script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'Python script {SCRIPT_PATH} is not a regular file.'

    fixed_edges = [
        (10, 20), (20, 30), (30, 40), (40, 10),
        (1, 2), (2, 3), (3, 4), (4, 1),
        (4, 5), (20, 25), (25, 26), (26, 20),
    ]
    create_database(fixed_edges)
    lines = execute_and_read()
    expected_lines = ['1,2,3,4', '10,20,30,40']
    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} cycles, but found {len(lines)}.'
    assert lines == expected_lines, f'Content of {LOG_PATH} does not match expected output.\nExpected: {expected_lines}\nGot: {lines}'


def test_cycles_on_unpredictable_databases():
    rng = random.SystemRandom()
    for _ in range(4):
        accounts = sorted(rng.sample(range(100, 10000), 9))
        edges = set()

        cycle1 = rng.sample(accounts, 4)
        cycle2 = rng.sample(accounts, 4)
        for cycle in (cycle1, cycle2):
            edges.update((cycle[i], cycle[(i + 1) % 4]) for i in range(4))

        for sender in accounts:
            for receiver in accounts:
                if sender != receiver and rng.random() < 0.16:
                    edges.add((sender, receiver))

        # Self-transfers and duplicate rows must not create extra cycles.
        edges.add((accounts[0], accounts[0]))
        rows = list(edges) + [next(iter(edges))]
        rng.shuffle(rows)
        create_database(rows)

        expected = expected_cycles(rows)
        actual = execute_and_read()
        assert actual == expected, f'Incorrect cycles for generated transfer graph.\nExpected: {expected}\nGot: {actual}'


def test_optimize_sql_content():
    assert os.path.exists(SQL_PATH), f'SQL script {SQL_PATH} does not exist.'
    assert os.path.isfile(SQL_PATH), f'SQL script {SQL_PATH} is not a regular file.'

    with open(SQL_PATH, 'r') as f:
        content = f.read()
    lowered = content.lower()

    # Preserve the original content assertions.
    assert 'create index' in lowered, f"No 'CREATE INDEX' statement found in {SQL_PATH}."
    assert 'sender_id' in lowered, f"'sender_id' column not found in the index definition in {SQL_PATH}."
    assert 'receiver_id' in lowered, f"'receiver_id' column not found in the index definition in {SQL_PATH}."

    conn = sqlite3.connect(':memory:')
    conn.execute('CREATE TABLE transfers (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp TEXT)')
    try:
        # execute(), unlike executescript(), rejects a second SQL statement.
        conn.execute(content)
    except sqlite3.Error as exc:
        raise AssertionError(f'{SQL_PATH} must contain one executable CREATE INDEX statement: {exc}')

    indexes = conn.execute("PRAGMA index_list('transfers')").fetchall()
    assert len(indexes) == 1, f'Expected exactly one index on transfers, found {len(indexes)}.'
    _, index_name, is_unique, _, is_partial = indexes[0]
    assert not is_unique, 'The optimization must be a normal non-unique CREATE INDEX.'
    assert not is_partial, 'The composite index must cover all transfers, not only a partial subset.'

    columns = [row[2] for row in conn.execute(f'PRAGMA index_info({index_name!r})').fetchall()]
    assert columns == ['sender_id', 'receiver_id'], (
        'The index must be a composite index on sender_id followed by receiver_id; '
        f'got {columns}.'
    )
    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
