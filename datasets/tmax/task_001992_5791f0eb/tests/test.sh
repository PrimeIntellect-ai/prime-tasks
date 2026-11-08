#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = "/home/user/dependency_graph.db"
SCRIPT_PATH = "/home/user/analyze_subgraph.py"
OUTPUT_PATH = "/home/user/output_100.json"
REQUIRED_KEYS = {"node_id", "category", "score", "category_rank"}


def test_index_created():
    """Verify that the correctly ordered composite index exists."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND name='idx_category_score'")
        row = cursor.fetchone()

        assert row is not None, "Index 'idx_category_score' is missing from the database"
        index_sql = row[1].lower() if row[1] else ""
        assert "category" in index_sql and "score" in index_sql, \
            "Index 'idx_category_score' does not appear to cover 'category' and 'score'"

        cursor.execute("PRAGMA index_list('node_metrics')")
        assert any(item[1] == "idx_category_score" for item in cursor.fetchall()), \
            "Index 'idx_category_score' must index node_metrics"

        cursor.execute("PRAGMA index_xinfo('idx_category_score')")
        key_columns = [(item[2], item[3]) for item in cursor.fetchall() if item[5] == 1 and item[1] >= 0]
        assert len(key_columns) >= 2, "idx_category_score must be a composite index"
        assert key_columns[0] == ("category", 0), \
            "The first indexed column must be category in ascending order"
        assert key_columns[1] == ("score", 1), \
            "The second indexed column must be score in descending order"
    finally:
        conn.close()


def test_script_exists():
    """Verify that the analyze_subgraph.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def _resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return assignments.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _resolve_string(node.left, assignments)
        right = _resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    return None


def test_script_uses_parameterized_window_query():
    """Require an executed RANK window query with a bound source parameter."""
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()

    tree = ast.parse(source, filename=SCRIPT_PATH)
    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = _resolve_string(node.value, assignments) if node.value is not None else None
            if value is None:
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = value

    found = False
    placeholder = re.compile(r"\?|(?<!:):[A-Za-z_][A-Za-z0-9_]*|@[A-Za-z_][A-Za-z0-9_]*|\$[A-Za-z_][A-Za-z0-9_]*")
    rank_window = re.compile(r"\bRANK\s*\(\s*\)\s*OVER\b", re.IGNORECASE | re.DOTALL)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != "execute" or not node.args:
            continue
        sql = _resolve_string(node.args[0], assignments)
        has_parameters = len(node.args) >= 2 or any(k.arg == "parameters" for k in node.keywords)
        if sql and rank_window.search(sql) and placeholder.search(sql) and has_parameters:
            found = True
            break

    assert found, \
        "The script must execute a parameterized SQL query that uses RANK() OVER(...)"


def _expected_for_source(source_node):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """SELECT DISTINCT m.node_id, m.category, m.score
               FROM edges AS e
               JOIN node_metrics AS m ON m.node_id = e.target
               WHERE e.source = ?""",
            (source_node,),
        ).fetchall()
    finally:
        conn.close()

    by_category = {}
    for node_id, category, score in rows:
        by_category.setdefault(category, []).append((node_id, score))

    result = []
    for category, members in by_category.items():
        members.sort(key=lambda item: (-item[1], item[0]))
        previous_score = object()
        current_rank = 0
        for position, (node_id, score) in enumerate(members, start=1):
            if score != previous_score:
                current_rank = position
                previous_score = score
            result.append({
                "node_id": node_id,
                "category": category,
                "score": score,
                "category_rank": current_rank,
            })

    result.sort(key=lambda item: (item["category_rank"], item["node_id"]))
    return result


def _validate_payload(data):
    assert isinstance(data, list), "JSON output must be a list of dictionaries"
    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be a dictionary"
        for key in ["node_id", "category", "score", "category_rank"]:
            assert key in item, f"Missing key '{key}' in JSON output item: {item}"
        assert set(item) == REQUIRED_KEYS, f"Unexpected JSON keys in output item: {item}"
        assert type(item["node_id"]) is int, "node_id must be an integer"
        assert isinstance(item["category"], str), "category must be a string"
        assert type(item["score"]) in (int, float), "score must be numeric"
        assert type(item["category_rank"]) is int, "category_rank must be an integer"

    for current, nxt in zip(data, data[1:]):
        if current["category_rank"] > nxt["category_rank"]:
            pytest.fail("JSON output is not sorted by category_rank ascending")
        if (current["category_rank"] == nxt["category_rank"] and
                current["node_id"] > nxt["node_id"]):
            pytest.fail("JSON output is not sorted by node_id ascending when ranks are equal")


def _run_script(source_node):
    completed = subprocess.run(
        ["python3", SCRIPT_PATH, str(source_node)],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert completed.returncode == 0, \
        f"Script failed for source {source_node}: {completed.stderr}"
    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Script stdout is not strictly JSON: {exc}; stdout={completed.stdout!r}")
    _validate_payload(data)
    return data


def test_output_json_validity_and_schema():
    """Verify that output_100.json exists, is valid JSON, and has the correct schema."""
    assert os.path.exists(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON")

    _validate_payload(data)


def test_output_json_logic():
    """Verify output_100 and actual script execution against database-derived results."""
    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    expected_node_ids = {250, 310, 405, 800, 912}
    actual_node_ids = {item["node_id"] for item in data}
    assert actual_node_ids == expected_node_ids, \
        f"Expected node IDs {expected_node_ids}, but got {actual_node_ids}"

    expected = _expected_for_source(100)
    assert data == expected, "output_100.json does not contain the correct metrics and ranks"
    assert _run_script(100) == expected, \
        "Executing analyze_subgraph.py for source 100 produced incorrect output"


def test_script_on_unseen_subgraph():
    """Exercise the script on verifier-created data with ties and nontrivial ranks."""
    token = secrets.token_hex(6)
    source_node = 1_500_000_000 + secrets.randbelow(100_000_000)
    base_node = 1_700_000_000 + secrets.randbelow(100_000_000)
    category_a = "verify_A_" + token
    category_b = "verify_B_" + token
    metrics = [
        (base_node + 1, category_a, 91.25),
        (base_node + 2, category_a, 91.25),
        (base_node + 3, category_a, 72.50),
        (base_node + 4, category_b, 88.75),
        (base_node + 5, category_b, 64.00),
        (base_node + 6, category_b, 64.00),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany(
            "INSERT INTO node_metrics (node_id, category, score) VALUES (?, ?, ?)", metrics
        )
        conn.executemany(
            "INSERT INTO edges (source, target) VALUES (?, ?)",
            [(source_node, row[0]) for row in metrics],
        )
        conn.commit()
    finally:
        conn.close()

    try:
        expected = _expected_for_source(source_node)
        actual = _run_script(source_node)
        assert actual == expected, \
            "Script did not return database-derived scores and window ranks for an unseen source"
    finally:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("DELETE FROM edges WHERE source = ?", (source_node,))
            conn.executemany("DELETE FROM node_metrics WHERE node_id = ?", [(row[0],) for row in metrics])
            conn.commit()
        finally:
            conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
