#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess

SOURCE = '/home/user/process_backups.cpp'
EXECUTABLE = '/home/user/process_backups'
DATABASE = '/home/user/backup_network.db'
OUTPUT = '/home/user/backup_plan.csv'


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_cpp_source_exists():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."


def test_source_uses_window_function():
    with open(SOURCE, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    source_without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', ' ', source, flags=re.S)
    window_call = re.compile(
        r'\b[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*OVER\s*\(', re.I | re.S
    )
    assert window_call.search(source_without_comments), (
        'The source does not contain an SQL window-function expression using OVER(...).'
    )


def compile_submission():
    if os.path.lexists(EXECUTABLE):
        remove_path(EXECUTABLE)
    result = subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-lsqlite3', '-o', EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stdout}{result.stderr}"
    assert os.path.isfile(EXECUTABLE), 'Compilation did not create the required executable.'
    assert os.access(EXECUTABLE, os.X_OK), 'Compiled output is not executable.'


def create_database(backups, edges):
    for suffix in ('', '-wal', '-shm'):
        path = DATABASE + suffix
        if os.path.lexists(path):
            remove_path(path)
    conn = sqlite3.connect(DATABASE)
    try:
        conn.executescript('''
            CREATE TABLE backups (
                id TEXT PRIMARY KEY,
                node_id INTEGER,
                timestamp INTEGER,
                size_bytes INTEGER
            );
            CREATE TABLE network (
                source_node INTEGER,
                dest_node INTEGER,
                transfer_cost INTEGER
            );
        ''')
        conn.executemany(
            'INSERT INTO backups (id, node_id, timestamp, size_bytes) VALUES (?, ?, ?, ?)',
            backups,
        )
        conn.executemany(
            'INSERT INTO network (source_node, dest_node, transfer_cost) VALUES (?, ?, ?)',
            edges,
        )
        conn.commit()
    finally:
        conn.close()
    os.chmod(DATABASE, 0o666)


def run_program():
    if os.path.lexists(OUTPUT):
        remove_path(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executable exited with status {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_csv():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    with open(OUTPUT, 'r', newline='') as f:
        return list(csv.reader(f))


def test_csv_output():
    expected_rows = [
        ['node_id', 'backup_id', 'size_bytes', 'path_cost'],
        ['1', 'b2', '150', '10'],
        ['2', 'b3', '200', '15'],
        ['3', 'b5', '350', '15'],
        ['4', 'b6', '400', '16']
    ]
    actual_rows = read_csv()
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def install_original_fixture():
    backups = [
        ('b1', 1, 1600000000, 100),
        ('b2', 1, 1600000100, 150),
        ('b3', 2, 1600000050, 200),
        ('b4', 3, 1600000000, 300),
        ('b5', 3, 1600000200, 350),
        ('b6', 4, 1600000300, 400),
        ('b7', 5, 1600000000, 500),
    ]
    edges = [
        (1, 0, 10), (2, 1, 5), (2, 3, 2), (3, 0, 15),
        (4, 3, 5), (4, 2, 1), (5, 6, 10),
    ]
    create_database(backups, edges)


def shortest_cost(source, graph):
    queue = [(0, source)]
    best = {source: 0}
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != best[node]:
            continue
        if node == 0:
            return cost
        for dest, edge_cost in graph.get(node, []):
            new_cost = cost + edge_cost
            if new_cost < best.get(dest, float('inf')):
                best[dest] = new_cost
                heapq.heappush(queue, (new_cost, dest))
    return None


def randomized_fixture():
    rng = random.SystemRandom()
    a, b, c, d, e, f = rng.sample(range(10, 2000), 6)
    p, q, r, s = [rng.randint(2, 40) for _ in range(4)]
    edges = [
        (a, 0, p),
        (b, a, q),
        (b, 0, p + q + rng.randint(5, 30)),
        (c, b, r),
        (c, 0, p + q + r + rng.randint(5, 30)),
        (d, c, s),
        (d, a, s + r + q + rng.randint(5, 30)),
        (e, f, rng.randint(1, 30)),
        (f, e, rng.randint(1, 30)),
        (0, d, rng.randint(1, 30)),
    ]
    rng.shuffle(edges)

    backups = []
    latest = {}
    base = rng.randint(1700000000, 1900000000)
    for index, node in enumerate([a, b, c, d, e]):
        old_id = 'old_' + secrets.token_hex(6)
        new_id = 'new_' + secrets.token_hex(6)
        old_size = rng.randint(1000, 50000)
        new_size = rng.randint(50001, 100000)
        backups.append((old_id, node, base + index * 100, old_size))
        backups.append((new_id, node, base + index * 100 + rng.randint(1, 90), new_size))
        latest[node] = (new_id, new_size)
    backups.append(('archive_' + secrets.token_hex(6), 0, base + 9999, 123456))
    rng.shuffle(backups)

    graph = {}
    for source, dest, cost in edges:
        graph.setdefault(source, []).append((dest, cost))

    expected = [['node_id', 'backup_id', 'size_bytes', 'path_cost']]
    for node in sorted(latest):
        cost = shortest_cost(node, graph)
        if cost is not None:
            backup_id, size = latest[node]
            expected.append([str(node), backup_id, str(size), str(cost)])
    return backups, edges, expected


def test_randomized_execution():
    for _ in range(2):
        backups, edges, expected = randomized_fixture()
        create_database(backups, edges)
        run_program()
        actual = read_csv()
        assert actual == expected, f"Randomized database produced incorrect CSV. Expected {expected}, got {actual}."


def main():
    test_cpp_source_exists()
    test_executable_exists()
    test_source_uses_window_function()
    compile_submission()

    install_original_fixture()
    run_program()
    test_csv_output()

    test_randomized_execution()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
