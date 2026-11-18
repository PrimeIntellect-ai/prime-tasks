#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
from pathlib import Path

CPP_PATH = Path('/home/user/analyze_graph.cpp')
RESULT_PATH = Path('/home/user/result.txt')
DB_PATH = Path('/home/user/system_graph.db')
EXE_PATH = Path('/tmp/analyze_graph_verifier')


def read_result():
    assert RESULT_PATH.is_file(), f'Result file {RESULT_PATH} is missing after running the C++ program.'
    content = RESULT_PATH.read_text().strip().splitlines()
    return [line.strip() for line in content if line.strip()]


def run_program():
    if RESULT_PATH.exists():
        RESULT_PATH.unlink()
    completed = subprocess.run(
        [str(EXE_PATH)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f'C++ program exited with status {completed.returncode}. '
        f'stdout: {completed.stdout!r}; stderr: {completed.stderr!r}'
    )


def expected_original_result():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            SELECT n.identifier, COUNT(e.dst_id) as out_degree
            FROM sys_nodes n
            JOIN sys_edges e ON n.node_id = e.src_id
            WHERE e.rel_type = 'DEPENDS_ON'
            GROUP BY n.node_id, n.identifier
            ORDER BY out_degree DESC, n.identifier ASC
            LIMIT 3
        ''').fetchall()
        return [row[0] for row in rows]
    finally:
        conn.close()


def install_dynamic_database():
    if DB_PATH.exists():
        DB_PATH.unlink()

    token = secrets.token_hex(8)
    names = [f'Entity_{token}_{secrets.token_hex(4)}' for _ in range(8)]
    degrees = [1, 4, 4, 5, 2, 0, 3, 1]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript('''
            CREATE TABLE sys_nodes (
                node_id INTEGER PRIMARY KEY,
                identifier TEXT NOT NULL
            );
            CREATE TABLE sys_edges (
                src_id INTEGER,
                dst_id INTEGER,
                rel_type TEXT,
                FOREIGN KEY(src_id) REFERENCES sys_nodes(node_id),
                FOREIGN KEY(dst_id) REFERENCES sys_nodes(node_id)
            );
        ''')
        conn.executemany(
            'INSERT INTO sys_nodes(node_id, identifier) VALUES (?, ?)',
            [(i + 1, name) for i, name in enumerate(names)],
        )

        edges = []
        for src_id, degree in enumerate(degrees, start=1):
            destinations = [((src_id + offset) % len(names)) + 1 for offset in range(degree)]
            for dst_id in destinations:
                edges.append((src_id, dst_id, 'DEPENDS_ON'))
            if destinations:
                # Duplicate edges must not increase distinct out-degree.
                edges.append((src_id, destinations[0], 'DEPENDS_ON'))
            edges.append((src_id, ((src_id + 3) % len(names)) + 1, 'LOGS_TO'))
        conn.executemany(
            'INSERT INTO sys_edges(src_id, dst_id, rel_type) VALUES (?, ?, ?)',
            edges,
        )
        conn.commit()

        rows = conn.execute('''
            SELECT n.identifier, COUNT(DISTINCT e.dst_id) AS out_degree
            FROM sys_nodes n
            JOIN sys_edges e ON n.node_id = e.src_id
            WHERE e.rel_type = 'DEPENDS_ON'
            GROUP BY n.node_id, n.identifier
            ORDER BY out_degree DESC, n.identifier ASC
            LIMIT 3
        ''').fetchall()
        return [row[0] for row in rows]
    finally:
        conn.close()


def test_cpp_program_and_result():
    # Preserve the original existence assertions.
    assert RESULT_PATH.is_file(), f'Result file {RESULT_PATH} is missing. Did you run your C++ program?'
    assert CPP_PATH.is_file(), f'C++ source file {CPP_PATH} is missing.'
    assert DB_PATH.is_file(), f'Database file {DB_PATH} is missing.'

    compilation = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(CPP_PATH), '-lsqlite3', '-o', str(EXE_PATH)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, (
        f'Failed to compile analyze_graph.cpp: {compilation.stderr}'
    )

    linked = subprocess.run(
        ['ldd', str(EXE_PATH)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert linked.returncode == 0 and 'libsqlite3' in linked.stdout, (
        'The compiled program must use the SQLite C/C++ library.'
    )

    original_db = DB_PATH.read_bytes()
    try:
        dynamic_expected = install_dynamic_database()
        run_program()
        dynamic_actual = read_result()
        assert dynamic_actual == dynamic_expected, (
            f'On a validation graph, expected {dynamic_expected}, but got {dynamic_actual}. '
            'Compute distinct DEPENDS_ON out-degree from the database at runtime.'
        )

        DB_PATH.unlink(missing_ok=True)
        DB_PATH.write_bytes(original_db)
        original_expected = expected_original_result()
        run_program()
        original_actual = read_result()
        assert original_actual == original_expected, (
            f'Expected the top 3 entities to be {original_expected}, but got {original_actual}. '
            'Make sure to sort by out-degree DESC and then alphabetically ASC.'
        )
    finally:
        DB_PATH.unlink(missing_ok=True)
        DB_PATH.write_bytes(original_db)


if __name__ == '__main__':
    test_cpp_program_and_result()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
