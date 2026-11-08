#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
from pathlib import Path

import pytest

DB_PATH = "/home/user/graph.db"
CSV_PATH = "/home/user/triangles.csv"
SOURCE_PATH = "/home/user/query_graph.c"
BINARY_PATH = "/home/user/query_graph"


def create_database(rows):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE edges (src TEXT, dst TEXT, relation TEXT, timestamp INTEGER, is_deleted INTEGER)")
    conn.executemany("INSERT INTO edges VALUES (?, ?, ?, ?, ?)", rows)
    conn.execute("CREATE INDEX bad_idx ON edges(src)")
    conn.commit()
    conn.close()


def original_rows():
    return [
        ("A", "B", "KNOWS", 100, 0),
        ("B", "C", "KNOWS", 101, 0),
        ("C", "A", "KNOWS", 102, 0),
        ("A", "B", "KNOWS", 50, 1),
        ("C", "D", "KNOWS", 103, 0),
        ("D", "E", "KNOWS", 104, 0),
        ("E", "C", "KNOWS", 105, 0),
        ("E", "C", "KNOWS", 106, 1),
        ("X", "Y", "KNOWS", 200, 0),
        ("Y", "Z", "KNOWS", 200, 0),
        ("Z", "X", "KNOWS", 200, 0),
        ("X", "Z", "LIKES", 200, 0),
    ]


def run_program():
    result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"query_graph exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_optimized_covering_index():
    conn = sqlite3.connect(DB_PATH)
    try:
        sql_row = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='good_idx'"
        ).fetchone()
        assert sql_row is not None, "Index 'good_idx' was not created in the database."

        info = conn.execute("PRAGMA index_xinfo('good_idx')").fetchall()
        key_columns = [row[2] for row in info if row[5] == 1 and row[1] >= 0]
        assert key_columns[:4] == ["relation", "src", "dst", "timestamp"], (
            "good_idx must begin with (relation, src, dst, timestamp) so relation "
            "filtering and latest-row lookup are indexed; got " + repr(key_columns)
        )
        assert "is_deleted" in key_columns[4:], (
            "good_idx is not covering: is_deleted must be stored in the index; got "
            + repr(key_columns)
        )
    finally:
        conn.close()


def expected_triangles(rows):
    latest = {}
    for src, dst, relation, timestamp, is_deleted in rows:
        key = (src, dst)
        if key not in latest or timestamp > latest[key][1]:
            latest[key] = (relation, timestamp, is_deleted)

    active = {
        pair for pair, (relation, _timestamp, is_deleted) in latest.items()
        if relation == "KNOWS" and is_deleted == 0
    }
    nodes = {node for edge in active for node in edge}
    triangles = set()
    for a in nodes:
        for b in nodes:
            if (a, b) not in active:
                continue
            for c in nodes:
                if len({a, b, c}) == 3 and (b, c) in active and (c, a) in active:
                    triangles.add(tuple(sorted((a, b, c))))
    return sorted(triangles)


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_original_database():
    source = Path(SOURCE_PATH)
    assert source.is_file() and not source.is_symlink(), (
        f"A regular C source file is required at {SOURCE_PATH}."
    )

    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        f"Compilation did not produce executable {BINARY_PATH}."
    )

    create_database(original_rows())
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass
    run_program()


def test_bad_idx_dropped():
    """Test that 'bad_idx' index has been dropped."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='bad_idx';")
    result = cursor.fetchone()
    conn.close()
    assert result is None, "Index 'bad_idx' still exists in the database. It should have been dropped."


def test_good_idx_created():
    """Test that 'good_idx' index has been created."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='good_idx';")
    result = cursor.fetchone()
    conn.close()
    assert result is not None, "Index 'good_idx' was not created in the database."


def test_triangles_csv_content():
    """Test that the triangles.csv file contains the correct output."""
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} is missing."

    with open(CSV_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 1, "CSV file is empty."
    assert lines[0] == "node1,node2,node3", f"CSV header is incorrect. Expected 'node1,node2,node3', got '{lines[0]}'."

    expected_rows = ["A,B,C", "X,Y,Z"]
    actual_rows = lines[1:]
    assert actual_rows == expected_rows, f"CSV content is incorrect. Expected {expected_rows}, got {actual_rows}."


def test_good_idx_is_requested_covering_index():
    assert_optimized_covering_index()


def test_pipeline_on_unseen_database():
    token = secrets.token_hex(6)
    n = [f"n{i}_{token}" for i in range(9)]
    a, b, c, d, e, f, g, h, i = n

    rows = [
        # Active triangle with stale history.
        (a, b, "KNOWS", 5, 1),
        (a, b, "KNOWS", 20, 0),
        (b, c, "KNOWS", 21, 0),
        (c, a, "KNOWS", 22, 0),
        # A second active triangle whose deletion is older than its live row.
        (d, e, "KNOWS", 30, 1),
        (d, e, "KNOWS", 40, 0),
        (e, f, "KNOWS", 41, 0),
        (f, d, "KNOWS", 42, 0),
        # Looks like a triangle historically, but the latest g->h row is LIKES.
        (g, h, "KNOWS", 50, 0),
        (g, h, "LIKES", 60, 0),
        (h, i, "KNOWS", 51, 0),
        (i, g, "KNOWS", 52, 0),
        # Noise and a latest deletion.
        (c, d, "KNOWS", 70, 0),
        (d, a, "KNOWS", 71, 0),
        (a, c, "KNOWS", 72, 0),
        (a, c, "KNOWS", 73, 1),
    ]
    expected = expected_triangles(rows)

    create_database(rows)
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass
    run_program()

    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='index' AND name='bad_idx'"
        ).fetchone() is None, "bad_idx was not dropped on the unseen database."
        assert conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='index' AND name='good_idx'"
        ).fetchone() is not None, "good_idx was not created on the unseen database."
    finally:
        conn.close()
    assert_optimized_covering_index()

    assert os.path.isfile(CSV_PATH), "The program did not create triangles.csv."
    with open(CSV_PATH, "r", newline="") as csv_file:
        lines = csv_file.read().splitlines()
    expected_lines = ["node1,node2,node3"] + [",".join(row) for row in expected]
    assert lines == expected_lines, (
        f"CSV output for the unseen database is incorrect. Expected {expected_lines}, got {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
