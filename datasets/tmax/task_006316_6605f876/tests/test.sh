#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import sqlite3
import subprocess
from pathlib import Path

import pytest

DB_PATH = "/home/user/data/architecture.db"
SCRIPT_PATH = "/home/user/run_etl.py"
CSV_PATH = "/home/user/extracted_paths.csv"
LOG_PATH = "/home/user/query_plan.log"

QUERY = """
    SELECT e1.source, e2.source, e3.source, e3.target
    FROM edges e1
    JOIN edges e2 ON e1.target = e2.source
    JOIN edges e3 ON e2.target = e3.source
    JOIN nodes n1 ON e1.source = n1.id
    JOIN nodes n4 ON e3.target = n4.id
    WHERE e1.relation = 'calls'
      AND e2.relation = 'calls'
      AND e3.relation = 'calls'
      AND n1.type = 'Gateway'
      AND n4.type = 'Database'
    ORDER BY e1.source, e2.source, e3.source, e3.target
"""


def canonical_data():
    rng = random.Random(42)
    nodes = []
    for i in range(50):
        nodes.append((f"gw_{i}", "Gateway"))
    for i in range(500):
        nodes.append((f"svc_{i}", "Service"))
    for i in range(100):
        nodes.append((f"db_{i}", "Database"))

    edges = []
    for i in range(50):
        for _ in range(rng.randint(1, 5)):
            edges.append((f"gw_{i}", f"svc_{rng.randint(0, 199)}", "calls"))
    for i in range(200):
        for _ in range(rng.randint(0, 4)):
            edges.append((f"svc_{i}", f"svc_{rng.randint(200, 499)}", "calls"))
    for i in range(200, 500):
        for _ in range(rng.randint(0, 2)):
            edges.append((f"svc_{i}", f"db_{rng.randint(0, 99)}", "calls"))
    for _ in range(1000):
        edges.append((f"svc_{rng.randint(0, 499)}", f"svc_{rng.randint(0, 499)}", "depends_on"))
    return nodes, edges


EXPECTED_NODES, EXPECTED_EDGES = canonical_data()


def assert_tables_unchanged(conn):
    node_columns = conn.execute("PRAGMA table_info(nodes)").fetchall()
    edge_columns = conn.execute("PRAGMA table_info(edges)").fetchall()
    assert [(r[1], r[2], r[5]) for r in node_columns] == [
        ("id", "TEXT", 1), ("type", "TEXT", 0)
    ], "The nodes table schema was modified."
    assert [(r[1], r[2], r[5]) for r in edge_columns] == [
        ("source", "TEXT", 0), ("target", "TEXT", 0), ("relation", "TEXT", 0)
    ], "The edges table schema was modified."

    unexpected = conn.execute("""
        SELECT type, name FROM sqlite_master
        WHERE type IN ('trigger', 'view')
    """).fetchall()
    assert unexpected == [], "Only indexes may be added or removed."

    actual_nodes = conn.execute("SELECT id, type FROM nodes ORDER BY id, type").fetchall()
    actual_edges = conn.execute(
        "SELECT source, target, relation FROM edges ORDER BY source, target, relation"
    ).fetchall()
    assert actual_nodes == sorted(EXPECTED_NODES), "Data in the nodes table was modified."
    assert actual_edges == sorted(EXPECTED_EDGES), "Data in the edges table was modified."


def expected_path_rows():
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT)")
    conn.execute("CREATE TABLE edges (source TEXT, target TEXT, relation TEXT)")
    conn.executemany("INSERT INTO nodes VALUES (?, ?)", EXPECTED_NODES)
    conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", EXPECTED_EDGES)
    rows = conn.execute(QUERY).fetchall()
    conn.close()
    return rows


EXPECTED_ROWS = expected_path_rows()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    script = Path(SCRIPT_PATH)
    assert script.exists(), f"Python ETL script missing at {SCRIPT_PATH}"
    assert script.is_file(), f"ETL script is not a regular file: {SCRIPT_PATH}"
    assert os.path.exists(DB_PATH), "Database file is missing."

    conn = sqlite3.connect(DB_PATH)
    try:
        # Check the post-agent database before changing anything for the execution test.
        assert_tables_unchanged(conn)

        # Restore only the original index state so the submitted script is exercised
        # from the state described by the task, including the bad index it must drop.
        indexes = conn.execute("""
            SELECT name FROM sqlite_master
            WHERE type='index' AND name NOT LIKE 'sqlite_autoindex_%'
        """).fetchall()
        for (name,) in indexes:
            conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')
        conn.execute("CREATE INDEX idx_bad_edges ON edges(source) WHERE relation='depends_on'")
        conn.commit()
    finally:
        conn.close()

    for output in (CSV_PATH, LOG_PATH):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"ETL script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        assert_tables_unchanged(conn)
    finally:
        conn.close()


def test_idx_bad_edges_dropped():
    assert os.path.exists(DB_PATH), "Database file is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_bad_edges'")
    index = cursor.fetchone()
    conn.close()
    assert index is None, "The index 'idx_bad_edges' was not dropped."


def test_new_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name != 'sqlite_autoindex_nodes_1'")
    indexes = cursor.fetchall()
    conn.close()
    assert len(indexes) > 0, "No new indexes were created to optimize the query."


def test_extracted_paths_csv_exists_and_correct():
    assert os.path.exists(CSV_PATH), f"CSV file missing at {CSV_PATH}"
    expected_header = ["gateway_id", "service1_id", "service2_id", "database_id"]

    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")
        assert header == expected_header, (
            f"CSV header is incorrect. Expected {expected_header}, got {header}"
        )
        actual_rows = [tuple(row) for row in reader if row]

    assert len(actual_rows) == len(EXPECTED_ROWS), (
        f"Expected {len(EXPECTED_ROWS)} rows, got {len(actual_rows)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, EXPECTED_ROWS)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"


def test_query_plan_log():
    assert os.path.exists(LOG_PATH), f"Query plan log missing at {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert len(content) > 0, "Query plan log is empty."
    assert any(keyword in content.upper() for keyword in ["SCAN", "SEARCH", "INDEX", "CORRELATED"]), \
        "The file does not appear to contain a valid EXPLAIN QUERY PLAN output."

    conn = sqlite3.connect(DB_PATH)
    try:
        live_plan = conn.execute("EXPLAIN QUERY PLAN " + QUERY).fetchall()
    finally:
        conn.close()
    assert live_plan, "SQLite returned no query plan."
    for row in live_plan:
        detail = str(row[3])
        assert detail in content, f"Query plan log is missing live plan step: {detail}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
