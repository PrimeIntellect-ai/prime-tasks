#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import pytest

DB_PATH = "/home/user/backup.db"
SQL_PATH = "/home/user/index.sql"
JSONL_PATH = "/home/user/users_graph.jsonl"

ORIGINAL_NODES = [
    (1, "user", "alice"),
    (2, "user", "bob"),
    (3, "user", "charlie"),
    (4, "user", "dave"),
    (5, "user", "eve"),
    (10, "group", "admin"),
    (11, "group", "dev"),
    (12, "group", "qa"),
    (13, "group", "ops"),
]

ORIGINAL_EDGES = [
    (1, 1, 10, "member_of", 0),
    (2, 1, 11, "member_of", 0),
    (3, 2, 11, "member_of", 0),
    (4, 3, 12, "member_of", 1),
    (5, 3, 11, "member_of", 0),
    (6, 4, 13, "member_of", 0),
    (7, 4, 10, "member_of", 0),
    (8, 4, 12, "member_of", 1),
    (9, 5, 13, "member_of", 1),
]

EXPECTED_GRAPH = [
    {"username": "alice", "centrality": 2, "groups": ["admin", "dev"]},
    {"username": "bob", "centrality": 1, "groups": ["dev"]},
    {"username": "charlie", "centrality": 1, "groups": ["dev"]},
    {"username": "dave", "centrality": 2, "groups": ["admin", "ops"]},
]


def normalize_ddl(sql):
    return re.sub(r"\s+", " ", sql.strip().rstrip(";").strip()).lower()


def test_source_graph_was_not_modified():
    """The projection must be made from the original backup, not altered source rows."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        nodes = conn.execute("SELECT id, type, name FROM nodes ORDER BY id").fetchall()
        edges = conn.execute(
            "SELECT id, source, target, rel_type, deleted FROM edges ORDER BY id"
        ).fetchall()
    finally:
        conn.close()

    assert nodes == ORIGINAL_NODES, "The original nodes table was modified."
    assert edges == ORIGINAL_EDGES, "The original edges table was modified."


def test_index_exists_and_covers_columns():
    """Test that the index idx_edges_extract exists and covers the required columns."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_extract';")
    row = cursor.fetchone()
    assert row is not None, "Index 'idx_edges_extract' was not found in the database."

    cursor.execute("PRAGMA index_info('idx_edges_extract');")
    index_info = cursor.fetchall()
    conn.close()

    assert index_info, "Index 'idx_edges_extract' has no columns."

    indexed_columns = {info[2] for info in index_info}
    expected_columns = {"rel_type", "deleted", "source", "target"}

    missing_cols = expected_columns - indexed_columns
    assert not missing_cols, f"Index 'idx_edges_extract' is missing columns: {missing_cols}"
    assert indexed_columns == expected_columns, f"Index 'idx_edges_extract' contains unexpected columns: {indexed_columns - expected_columns}"


def test_sql_file_contents():
    """Test that index.sql is executable and is the DDL represented by the live index."""
    assert os.path.exists(SQL_PATH), f"SQL file {SQL_PATH} is missing."

    with open(SQL_PATH, "r") as f:
        original_content = f.read()
    content = original_content.lower()

    assert "create " in content and "index " in content, "The file must contain a CREATE INDEX statement."
    assert "idx_edges_extract" in content, "The SQL statement must name the index 'idx_edges_extract'."
    assert "edges" in content, "The SQL statement must create the index on the 'edges' table."

    expected_columns = ["rel_type", "deleted", "source", "target"]
    for col in expected_columns:
        assert col in content, f"The SQL statement is missing the column '{col}'."

    assert sqlite3.complete_statement(original_content), "index.sql does not contain a complete SQL statement."

    validation = sqlite3.connect(":memory:")
    try:
        validation.execute(
            "CREATE TABLE edges (id INTEGER PRIMARY KEY, source INTEGER, target INTEGER, rel_type TEXT, deleted INTEGER)"
        )
        try:
            validation.execute(original_content)
        except sqlite3.Error as exc:
            pytest.fail(f"index.sql is not a single executable CREATE INDEX statement: {exc}")

        row = validation.execute(
            "SELECT tbl_name, sql FROM sqlite_master WHERE type='index' AND name='idx_edges_extract'"
        ).fetchone()
        assert row is not None, "Executing index.sql did not create idx_edges_extract."
        assert row[0] == "edges", "Executing index.sql did not create the index on edges."
        file_index_sql = row[1]

        file_columns = [r[2] for r in validation.execute("PRAGMA index_info('idx_edges_extract')")]
        assert set(file_columns) == set(expected_columns), "The executable DDL does not define the required index columns."
        assert len(file_columns) == len(expected_columns), "The executable DDL contains duplicate or extra index columns."
    finally:
        validation.close()

    conn = sqlite3.connect(DB_PATH)
    try:
        live_row = conn.execute(
            "SELECT tbl_name, sql FROM sqlite_master WHERE type='index' AND name='idx_edges_extract'"
        ).fetchone()
    finally:
        conn.close()

    assert live_row is not None, "Index 'idx_edges_extract' was not found in the database."
    assert live_row[0] == "edges", "The live index is not on the edges table."
    assert normalize_ddl(file_index_sql) == normalize_ddl(live_row[1]), \
        "index.sql does not contain the executable DDL used for the live index."


def get_expected_graph():
    """Return the projection of the immutable original backup fixture."""
    return EXPECTED_GRAPH


def test_jsonl_output():
    """Test that the materialized JSONL graph matches the expected output exactly."""
    assert os.path.exists(JSONL_PATH), f"JSONL file {JSONL_PATH} is missing."

    expected_data = get_expected_graph()

    with open(JSONL_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    actual_data = []
    for i, line in enumerate(lines):
        try:
            obj = json.loads(line)
            actual_data.append(obj)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {JSONL_PATH} is not valid JSON: {line}")

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} lines in JSONL, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("username") == expected["username"], f"Line {i+1} username mismatch or out of alphabetical order."
        assert actual.get("centrality") == expected["centrality"], f"Line {i+1} centrality mismatch for user {expected['username']}."
        assert actual.get("groups") == expected["groups"], f"Line {i+1} groups mismatch or not sorted alphabetically for user {expected['username']}."

    assert actual_data == expected_data, "The JSONL output does not exactly match the expected graph projection."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
