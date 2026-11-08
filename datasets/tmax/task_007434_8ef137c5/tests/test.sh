#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess


def test_optimize_sql():
    sql_file = '/home/user/optimize.sql'
    assert os.path.exists(sql_file), f"{sql_file} does not exist."

    with open(sql_file, 'r') as f:
        content = f.read().lower()

    # Check that there is a CREATE INDEX statement on Edges(source_id)
    assert 'create index' in content, f"No CREATE INDEX statement found in {sql_file}."
    assert 'edges' in content and 'source_id' in content, f"Index does not appear to be on Edges(source_id) in {sql_file}."


def test_database_has_index():
    db_file = '/home/user/graph.db'
    assert os.path.exists(db_file), f"{db_file} does not exist."

    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    cursor.execute("SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='Edges'")
    indices = cursor.fetchall()

    has_source_id_index = False
    for (sql,) in indices:
        if sql and 'source_id' in sql.lower():
            has_source_id_index = True
            break

    conn.close()
    assert has_source_id_index, "The graph.db does not contain an index on Edges(source_id). Did you execute optimize.sql?"


def test_pipeline_executable_exists():
    exe_file = '/home/user/pipeline'
    assert os.path.exists(exe_file), f"Compiled executable {exe_file} does not exist."
    assert os.access(exe_file, os.X_OK), f"{exe_file} is not executable."
    with open(exe_file, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{exe_file} is not a compiled executable."


def test_final_nodes_csv():
    db_file = '/home/user/graph.db'
    csv_file = '/home/user/final_nodes.csv'
    exe_file = '/home/user/pipeline'

    # Derive the two worker results from the database, then restore a clean
    # initial Nodes state so stale database or CSV output cannot pass.
    query = """
        WITH RECURSIVE traverse(id) AS (
          SELECT target_id FROM Edges WHERE source_id = ?
          UNION
          SELECT Edges.target_id FROM Edges JOIN traverse ON Edges.source_id = traverse.id
        )
        SELECT SUM(weight) FROM Edges WHERE source_id IN traverse;
    """

    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    expected_values = {node_id: 0 for node_id in range(1, 6)}
    for node_id in (1, 2):
        cursor.execute(query, (node_id,))
        result = cursor.fetchone()[0]
        expected_values[node_id] = result if result is not None else 0
    cursor.execute("UPDATE Nodes SET value = 0")
    conn.commit()
    conn.close()

    if os.path.exists(csv_file):
        os.remove(csv_file)

    try:
        result = subprocess.run(
            [exe_file], cwd='/home/user', capture_output=True, text=True,
            timeout=15
        )
    except subprocess.TimeoutExpired:
        assert False, "pipeline did not complete; it appears to have deadlocked."

    assert result.returncode == 0, (
        f"pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    # Verify that both workers actually completed their updates.
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    cursor.execute("SELECT id, value FROM Nodes ORDER BY id ASC")
    final_rows = cursor.fetchall()
    conn.close()

    expected_rows = [(node_id, expected_values[node_id]) for node_id in range(1, 6)]
    assert final_rows == expected_rows, (
        f"Pipeline did not produce the expected final Nodes state. "
        f"Expected {expected_rows}, got {final_rows}."
    )

    assert os.path.exists(csv_file), f"{csv_file} does not exist after running the pipeline."
    with open(csv_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected 5 lines in {csv_file}, but got {len(lines)}."

    parsed_rows = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid CSV format: '{line}'"
        parsed_rows.append((int(parts[0]), int(parts[1])))

    # The CSV must be the actual final Nodes query result and sorted by id.
    assert parsed_rows == final_rows, (
        f"{csv_file} does not match the final Nodes state in ascending id order. "
        f"Expected {final_rows}, got {parsed_rows}."
    )


def test_pipeline_cpp_deadlock_fix():
    cpp_file = '/home/user/pipeline.cpp'
    assert os.path.exists(cpp_file), f"{cpp_file} does not exist."

    with open(cpp_file, 'r') as f:
        content = f.read()

    # Retain the source-level assertion while the execution test above verifies
    # that the selected strategy really allows both workers to finish.
    has_immediate = 'BEGIN IMMEDIATE' in content.upper()
    has_exclusive = 'BEGIN EXCLUSIVE' in content.upper()
    has_mutex = 'std::mutex' in content or 'std::lock_guard' in content

    assert has_immediate or has_exclusive or has_mutex, "pipeline.cpp does not appear to fix the deadlock. Need to use BEGIN IMMEDIATE, BEGIN EXCLUSIVE, or a mutex."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
