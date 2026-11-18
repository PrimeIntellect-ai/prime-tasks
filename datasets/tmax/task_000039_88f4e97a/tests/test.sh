#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import sqlite3
import subprocess

import networkx as nx
import pytest
from jsonschema import validate as schema_validate

DB_PATH = "/home/user/logistics.db"
NODES_PATH = "/home/user/data/nodes.csv"
EDGES_PATH = "/home/user/data/edges.csv"
RESULT_PATH = "/home/user/result.json"
SCHEMA_PATH = "/home/user/schema.json"
PLAN_PATH = "/home/user/query_plan.txt"
VALIDATE_PATH = "/home/user/validate.py"

EXPECTED_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "node_id": {"type": "string"},
            "node_type": {"type": "string"},
            "pagerank": {"type": "number"},
            "community_id": {"type": "integer"},
        },
        "required": ["node_id", "node_type", "pagerank", "community_id"],
        "additionalProperties": False,
    },
}


def compute_expected():
    with open(NODES_PATH, newline="") as f:
        nodes = list(csv.DictReader(f))
    with open(EDGES_PATH, newline="") as f:
        edges = list(csv.DictReader(f))

    graph = nx.Graph()
    graph.add_nodes_from(row["node_id"] for row in nodes)
    graph.add_edges_from((row["src"], row["dst"]) for row in edges)

    pagerank = nx.pagerank(graph)
    communities = list(nx.algorithms.community.greedy_modularity_communities(graph))
    community_ids = {}
    for community_id, members in enumerate(communities):
        for node_id in members:
            community_ids[node_id] = community_id

    expected_rows = {
        row["node_id"]: {
            "node_id": row["node_id"],
            "node_type": row["node_type"],
            "pagerank": pagerank[row["node_id"]],
            "community_id": community_ids[row["node_id"]],
        }
        for row in nodes
    }

    expected_result = [
        row for row in expected_rows.values()
        if row["node_type"] == "Distribution Center" and row["pagerank"] > 0.01
    ]
    expected_result.sort(key=lambda row: (-row["pagerank"], row["node_id"]))
    expected_result = expected_result[5:10]
    return expected_rows, expected_result


EXPECTED_ROWS, EXPECTED_RESULT = compute_expected()


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='node_metrics'")
        assert cursor.fetchone() is not None, "Table 'node_metrics' does not exist in the database."

        cursor.execute("PRAGMA table_info(node_metrics)")
        columns = {row[1] for row in cursor.fetchall()}
        assert {"node_id", "node_type", "pagerank", "community_id"}.issubset(columns), \
            "node_metrics is missing one or more required columns."

        cursor.execute("SELECT node_id, node_type, pagerank, community_id FROM node_metrics")
        actual = cursor.fetchall()
        assert len(actual) == len(EXPECTED_ROWS), \
            f"Expected {len(EXPECTED_ROWS)} node_metrics rows, got {len(actual)}."
        assert len({row[0] for row in actual}) == len(actual), "node_metrics contains duplicate node_id rows."

        for node_id, node_type, pagerank, community_id in actual:
            assert node_id in EXPECTED_ROWS, f"Unexpected node_id in node_metrics: {node_id!r}."
            expected = EXPECTED_ROWS[node_id]
            assert node_type == expected["node_type"], f"Incorrect node_type for {node_id}."
            assert pagerank is not None and math.isclose(
                float(pagerank), expected["pagerank"], rel_tol=1e-9, abs_tol=1e-12
            ), f"Incorrect PageRank for {node_id}: expected {expected['pagerank']}, got {pagerank}."
            assert isinstance(community_id, int) and not isinstance(community_id, bool), \
                f"community_id for {node_id} is not an integer."
            assert community_id == expected["community_id"], \
                f"Incorrect community_id for {node_id}: expected {expected['community_id']}, got {community_id}."
    finally:
        conn.close()


def test_query_plan_exists():
    assert os.path.isfile(PLAN_PATH), f"Query plan file {PLAN_PATH} does not exist."
    with open(PLAN_PATH) as f:
        content = f.read().upper()
    assert any(keyword in content for keyword in ["SCAN", "SEARCH", "B-TREE", "LIST"]), \
        "query_plan.txt does not look like the output of EXPLAIN QUERY PLAN."

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "EXPLAIN QUERY PLAN "
            "SELECT node_id, node_type, pagerank, community_id "
            "FROM node_metrics "
            "WHERE node_type = ? AND pagerank > ? "
            "ORDER BY pagerank DESC, node_id ASC LIMIT 5 OFFSET 5",
            ("Distribution Center", 0.01),
        ).fetchall()
    finally:
        conn.close()

    normalized_content = " ".join(content.split())
    for row in rows:
        detail = " ".join(str(row[3]).upper().split())
        assert detail in normalized_content, \
            f"query_plan.txt does not contain the actual plan detail for the required query: {detail}"


def test_schema_is_original():
    assert os.path.isfile(SCHEMA_PATH), f"Schema file {SCHEMA_PATH} does not exist."
    with open(SCHEMA_PATH) as f:
        schema = json.load(f)
    assert schema == EXPECTED_SCHEMA, "schema.json was altered or does not contain the required schema."


def test_result_json_validity_and_invariants():
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."
    with open(RESULT_PATH) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} is not valid JSON.")

    schema_validate(instance=data, schema=EXPECTED_SCHEMA)
    assert isinstance(data, list), "Result JSON must be an array."
    assert len(data) == 5, f"Expected exactly 5 results (page 2, size 5), got {len(data)}."

    prev_pr = float("inf")
    prev_id = ""
    for item in data:
        assert isinstance(item, dict), "Each item in the result array must be an object."
        assert "node_id" in item, "Missing 'node_id'."
        assert "node_type" in item, "Missing 'node_type'."
        assert "pagerank" in item, "Missing 'pagerank'."
        assert "community_id" in item, "Missing 'community_id'."
        assert item["node_type"] == "Distribution Center", \
            f"Expected node_type 'Distribution Center', got {item['node_type']}."
        assert item["pagerank"] > 0.01, f"Expected pagerank > 0.01, got {item['pagerank']}."

        pr = item["pagerank"]
        nid = item["node_id"]
        if pr > prev_pr:
            pytest.fail("Results are not sorted descending by pagerank.")
        elif pr == prev_pr and nid < prev_id:
            pytest.fail("Tied pageranks are not sorted ascending by node_id.")
        prev_pr = pr
        prev_id = nid

    assert len(data) == len(EXPECTED_RESULT)
    for position, (actual, expected) in enumerate(zip(data, EXPECTED_RESULT), start=1):
        assert set(actual) == {"node_id", "node_type", "pagerank", "community_id"}
        assert actual["node_id"] == expected["node_id"], f"Wrong node on page 2 at position {position}."
        assert actual["node_type"] == expected["node_type"]
        assert actual["community_id"] == expected["community_id"], \
            f"Wrong community_id for result {actual['node_id']}."
        assert math.isclose(
            actual["pagerank"], expected["pagerank"], rel_tol=1e-9, abs_tol=1e-12
        ), f"Wrong PageRank for result {actual['node_id']}."


def test_validate_script_runs_and_rejects_invalid_data():
    assert os.path.isfile(VALIDATE_PATH), f"Validation script {VALIDATE_PATH} does not exist."
    with open(VALIDATE_PATH) as f:
        source = f.read()
    ast.parse(source)
    assert "jsonschema" in source, "validate.py does not use the jsonschema library."

    result = subprocess.run(["python3", VALIDATE_PATH], capture_output=True, text=True)
    assert result.returncode == 0, \
        f"validate.py failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    with open(RESULT_PATH, "rb") as f:
        original_result = f.read()
    try:
        invalid = json.loads(original_result)
        invalid[0]["unexpected_property"] = True
        with open(RESULT_PATH, "w") as f:
            json.dump(invalid, f)
        rejected = subprocess.run(["python3", VALIDATE_PATH], capture_output=True, text=True)
        assert rejected.returncode != 0, \
            "validate.py exited successfully for data that violates schema.json."
    finally:
        with open(RESULT_PATH, "wb") as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
