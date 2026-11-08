#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

DB_PATH = '/home/user/etl_data.db'
CPP_PATH = '/home/user/process_graph.cpp'
CSV_PATH = '/home/user/impact_page_2.csv'
EXE_PATH = '/tmp/process_graph_verifier'

def compute_expected_page():
    """
    Computes the expected downstream impact scores from the SQLite database
    and returns the expected rows for Page 2.
    """
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT id, name FROM nodes")
    nodes = {row[0]: row[1] for row in cursor.fetchall()}

    cursor.execute("SELECT source, target FROM edges")
    edges = cursor.fetchall()
    conn.close()

    # Build reverse graph (target -> sources) to find ancestors
    parents = {node_id: [] for node_id in nodes}
    for source, target in edges:
        parents[target].append(source)

    def get_ancestors(node_id):
        visited = set()
        stack = [node_id]
        while stack:
            curr = stack.pop()
            for p in parents[curr]:
                if p not in visited:
                    visited.add(p)
                    stack.append(p)
        return visited

    impacts = []
    for node_id, name in nodes.items():
        score = len(get_ancestors(node_id)) + 1
        impacts.append((node_id, name, score))

    # Sort: Downstream Impact descending, then ID ascending
    impacts.sort(key=lambda x: (-x[2], x[0]))

    # Page 2 (items 5-8), indices 4 to 7
    return impacts[4:8]

def assert_csv_matches(expected_data):
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"CSV file {CSV_PATH} is empty."

    expected_header = ['id', 'name', 'impact_score']
    assert rows[0] == expected_header, f"Invalid CSV header. Expected {expected_header}, got {rows[0]}."

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} rows of data, got {len(data_rows)}."

    for i, (exp_id, exp_name, exp_score) in enumerate(expected_data):
        actual_id, actual_name, actual_score = data_rows[i]

        assert int(actual_id) == exp_id, f"Row {i+1}: expected id {exp_id}, got {actual_id}."
        assert actual_name == exp_name, f"Row {i+1}: expected name '{exp_name}', got '{actual_name}'."
        assert int(actual_score) == exp_score, f"Row {i+1}: expected impact_score {exp_score}, got {actual_score}."

def test_cpp_file_exists():
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a file."

def test_csv_output_exists():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."

def test_csv_output_contents():
    if not os.path.exists(CSV_PATH):
        pytest.fail(f"Cannot verify contents because {CSV_PATH} does not exist.")

    expected_data = compute_expected_page()
    assert_csv_matches(expected_data)

def test_program_ingests_database_and_generates_output():
    # Exercise the compiled submission against a fresh, unpredictable DAG so a
    # hardcoded CSV or a program that ignores the database cannot pass.
    fd, backup_db = tempfile.mkstemp(prefix='etl_data_backup_', suffix='.db')
    os.close(fd)
    fd, generated_db = tempfile.mkstemp(prefix='etl_data_generated_', suffix='.db')
    os.close(fd)
    os.unlink(generated_db)
    fd, backup_csv = tempfile.mkstemp(prefix='impact_backup_', suffix='.csv')
    os.close(fd)

    shutil.copy2(DB_PATH, backup_db)
    shutil.copy2(CSV_PATH, backup_csv)

    try:
        rng = random.SystemRandom()
        node_ids = rng.sample(range(100, 10000), 12)
        names = [f"pkg_{secrets.token_hex(5)}" for _ in node_ids]

        # Include a diamond to verify unique-ancestor counting, then add
        # unpredictable forward edges while preserving acyclicity.
        edge_indexes = {(0, 1), (0, 2), (1, 3), (2, 3),
                        (3, 4), (3, 5), (4, 6), (5, 6),
                        (6, 7), (7, 8), (8, 9), (9, 10), (10, 11)}
        for i in range(len(node_ids)):
            for j in range(i + 1, len(node_ids)):
                if rng.random() < 0.16:
                    edge_indexes.add((i, j))

        conn = sqlite3.connect(generated_db)
        conn.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE edges (source INTEGER, target INTEGER)')
        conn.executemany('INSERT INTO nodes (id, name) VALUES (?, ?)',
                         list(zip(node_ids, names)))
        conn.executemany('INSERT INTO edges (source, target) VALUES (?, ?)',
                         [(node_ids[i], node_ids[j]) for i, j in edge_indexes])
        conn.commit()
        conn.close()
        os.chmod(generated_db, 0o644)
        os.replace(generated_db, DB_PATH)

        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

        subprocess.run([EXE_PATH], cwd='/home/user', check=True, timeout=20)
        expected_data = compute_expected_page()
        assert_csv_matches(expected_data)
    finally:
        shutil.copy2(backup_db, DB_PATH)
        shutil.copy2(backup_csv, CSV_PATH)
        for path in (backup_db, generated_db, backup_csv):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if g++ -std=c++17 -O2 -Wall -Wextra /home/user/process_graph.cpp -lsqlite3 -o /tmp/process_graph_verifier \
   && rm -f /home/user/impact_page_2.csv \
   && timeout 20s /tmp/process_graph_verifier \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
