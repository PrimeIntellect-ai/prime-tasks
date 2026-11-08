#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "analyze.go")
RESULTS = os.path.join(HOME, "results.json")
PLAN = os.path.join(HOME, "plan.txt")
SCHEMA = os.path.join(HOME, "schema.json")
DB = os.path.join(HOME, "graph.db")
BINARY = "/tmp/analyze_submission"


def load_json(path):
    assert os.path.isfile(path), f"Expected file at {path} does not exist."
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{path} does not contain valid JSON: {exc}")


def validate_schema_instance(instance, schema, where="$"):
    expected_type = schema.get("type")
    if expected_type == "array":
        assert isinstance(instance, list), f"{where} must be an array"
        item_schema = schema.get("items")
        if item_schema:
            for index, item in enumerate(instance):
                validate_schema_instance(item, item_schema, f"{where}[{index}]")
    elif expected_type == "object":
        assert isinstance(instance, dict), f"{where} must be an object"
        for required in schema.get("required", []):
            assert required in instance, f"{where} is missing required property {required!r}"
        properties = schema.get("properties", {})
        for key, value in instance.items():
            if key in properties:
                validate_schema_instance(value, properties[key], f"{where}.{key}")
        if schema.get("additionalProperties") is False:
            extras = set(instance) - set(properties)
            assert not extras, f"{where} has forbidden additional properties: {sorted(extras)}"
    elif expected_type == "integer":
        assert isinstance(instance, int) and not isinstance(instance, bool), f"{where} must be an integer"
    elif expected_type == "string":
        assert isinstance(instance, str), f"{where} must be a string"


def expected_rows(db_path):
    with sqlite3.connect(db_path) as conn:
        rows = conn.execute("""
            SELECT n.id, n.label, COUNT(e2.target)
            FROM nodes AS n
            LEFT JOIN edges AS e1 ON e1.source = n.id
            LEFT JOIN edges AS e2 ON e2.source = e1.target
            GROUP BY n.id, n.label
        """).fetchall()
    return {row[0]: (row[1], row[2]) for row in rows}


def assert_complete_correct_output(data, db_path):
    assert isinstance(data, list), "Expected JSON output to be an array."
    schema = load_json(SCHEMA)
    validate_schema_instance(data, schema)

    expected = expected_rows(db_path)
    actual = {}
    for item in data:
        node_id = item["node_id"]
        assert node_id not in actual, f"Duplicate result for node ID {node_id}"
        actual[node_id] = (item["node_label"], item["path_count"])

    assert set(actual) == set(expected), "Output must contain exactly one result for every node."
    assert actual == expected, "Node labels or length-2 path counts are incorrect."


def extract_query():
    with open(SOURCE, "r") as f:
        content = f.read()
    matches = re.findall(r"(?:\bvar\s+query\s*=|\bquery\s*:?=)\s*`([^`]*)`", content, re.DOTALL)
    matches = [q.strip().rstrip(";").strip() for q in matches if re.search(r"\bSELECT\b", q, re.I)]
    assert len(matches) == 1, "Could not identify exactly one SQL SELECT query assigned to query in analyze.go."
    return matches[0]


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert os.path.isfile(SOURCE), f"Expected Go script at {SOURCE} does not exist."
    proc = subprocess.run(
        ["go", "build", "-o", BINARY, "analyze.go"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert proc.returncode == 0, f"analyze.go failed to build:\n{proc.stderr}"


def run_binary(cwd):
    proc = subprocess.run(
        [BINARY], cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, f"analyze.go failed when executed:\n{proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Program stdout is not a JSON array: {exc}\nstdout:\n{proc.stdout}")


def test_results_json_exists_and_correct():
    data = load_json(RESULTS)
    assert isinstance(data, list), f"Expected JSON array in {RESULTS}."

    # Preserve the original fixed-value assertions.
    node_counts = {item.get("node_id"): item.get("path_count") for item in data}
    assert node_counts.get(1) == 2, "Node 1 should have exactly 2 length-2 paths."
    assert node_counts.get(2) == 2, "Node 2 should have exactly 2 length-2 paths."
    for node_id in [3, 4, 5]:
        if node_id in node_counts:
            assert node_counts[node_id] == 0, f"Node {node_id} should have 0 length-2 paths."

    # Require every database node, its real label, and its derived count.
    assert_complete_correct_output(data, DB)

    # results.json must be the output of the submitted program on graph.db.
    runtime_data = run_binary(HOME)
    assert_complete_correct_output(runtime_data, DB)
    assert runtime_data == data, "results.json does not match the submitted program's current stdout."


def test_program_on_unseen_database():
    # Exercise the compiled artifact on node IDs, labels, and edges not present in graph.db.
    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "graph.db")
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        ids = rng.sample(range(1000, 100000), 7)
        labels = [f"label-{uuid.uuid4().hex}" for _ in ids]
        edges = {(ids[0], ids[1]), (ids[1], ids[2]), (ids[1], ids[3]),
                 (ids[2], ids[4]), (ids[3], ids[4])}
        for source in ids:
            for target in ids:
                if source != target and rng.random() < 0.22:
                    edges.add((source, target))

        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT)")
            conn.execute("CREATE TABLE edges (source INTEGER, target INTEGER)")
            conn.executemany("INSERT INTO nodes(id, label) VALUES (?, ?)", zip(ids, labels))
            conn.executemany("INSERT INTO edges(source, target) VALUES (?, ?)", list(edges))

        runtime_data = run_binary(tmp)
        assert_complete_correct_output(runtime_data, db_path)

        # Also execute the exact SQL embedded in analyze.go against the unseen database.
        query = extract_query()
        with sqlite3.connect(db_path) as conn:
            rows = conn.execute(query).fetchall()
        assert len(rows) == len(ids), "The fixed SQL query must return every node."
        query_result = {}
        for row in rows:
            assert len(row) == 3, "The fixed SQL query must return ID, label, and path count."
            assert row[0] not in query_result, f"SQL query returned duplicate node ID {row[0]}"
            query_result[row[0]] = (row[1], row[2])
        assert query_result == expected_rows(db_path), "The SQL query does not compute length-2 path counts correctly."


def test_plan_txt_exists_and_contains_plan():
    assert os.path.isfile(PLAN), f"Expected query plan file at {PLAN} does not exist."
    with open(PLAN, "r") as f:
        content = f.read()
    upper = content.upper()

    # Preserve the original plan assertion.
    assert "SCAN" in upper or "SEARCH" in upper or "QUERY PLAN" in upper, \
        f"{PLAN} does not appear to contain a valid SQLite query plan."

    # The saved plan must contain the operations produced by EXPLAIN QUERY PLAN
    # for the exact query currently embedded in analyze.go.
    query = extract_query()
    with sqlite3.connect(DB) as conn:
        plan_rows = conn.execute("EXPLAIN QUERY PLAN " + query).fetchall()
    details = [re.sub(r"\s+", " ", str(row[3]).strip()).upper() for row in plan_rows]
    normalized_plan = re.sub(r"\s+", " ", content).upper()
    assert details, "EXPLAIN QUERY PLAN returned no operations."
    for detail in details:
        assert detail in normalized_plan, \
            f"plan.txt is not the plan for the exact query in analyze.go; missing operation: {detail}"


def test_analyze_go_uses_explicit_join():
    assert os.path.isfile(SOURCE), f"Expected Go script at {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original explicit-JOIN assertions.
    assert re.search(r"\bJOIN\b", content, re.IGNORECASE), "analyze.go must use explicit JOIN syntax."
    assert not re.search(r"FROM\s+\w+\s+\w+\s*,\s*\w+\s+\w+\s*,\s*\w+\s+\w+", content, re.IGNORECASE), \
        "analyze.go must not use implicit cross joins (comma-separated tables in FROM clause)."

    query = extract_query()
    assert re.search(r"\bJOIN\b", query, re.IGNORECASE), "The executed SQL query must use explicit JOIN syntax."
    assert not re.search(r"\bFROM\b[^;]*,", query, re.IGNORECASE | re.DOTALL), \
        "The executed SQL query must not use comma-separated FROM tables."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
