#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = "/home/user/process_citations.sh"
DB_PATH = "/home/user/citations.db"
JSON_PATH = "/home/user/citation_tree.json"
NODES_PATH = "/home/user/nodes.csv"
EDGES_PATH = "/home/user/edges.csv"


def execute_script():
    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def load_json():
    assert os.path.exists(JSON_PATH), f"JSON output file not found at {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {JSON_PATH}: {e}")


def assert_json_records(data, expected):
    assert isinstance(data, list), "JSON output should be a list of objects"
    assert len(data) == len(expected), (
        f"Expected {len(expected)} items in JSON array, got {len(data)}"
    )

    expected_keys = {"depth", "paper_id", "title"}
    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object"
        assert set(actual.keys()) == expected_keys, (
            f"Item at index {i} has incorrect keys. "
            f"Expected {expected_keys}, got {set(actual.keys())}"
        )
        assert actual["depth"] == wanted["depth"], (
            f"Incorrect depth at index {i}. Expected {wanted['depth']}, "
            f"got {actual['depth']}"
        )
        assert actual["paper_id"] == wanted["paper_id"], (
            f"Incorrect paper_id at index {i}. Expected {wanted['paper_id']}, "
            f"got {actual['paper_id']}"
        )
        assert actual["title"] == wanted["title"], (
            f"Incorrect title at index {i}. Expected {wanted['title']}, "
            f"got {actual['title']}"
        )


def assert_database(nodes, edges):
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Database path is not a file: {DB_PATH}"

    try:
        conn = sqlite3.connect(DB_PATH)
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        assert "nodes" in tables, "SQLite database is missing the nodes table"
        assert "edges" in tables, "SQLite database is missing the edges table"

        node_columns = [row[1] for row in conn.execute("PRAGMA table_info(nodes)")]
        edge_columns = [row[1] for row in conn.execute("PRAGMA table_info(edges)")]
        assert node_columns == ["id", "title", "year"], (
            f"Unexpected nodes columns: {node_columns}"
        )
        assert edge_columns == ["source", "target"], (
            f"Unexpected edges columns: {edge_columns}"
        )

        actual_nodes = sorted(
            tuple(str(value) for value in row)
            for row in conn.execute("SELECT id, title, year FROM nodes")
        )
        actual_edges = sorted(
            tuple(str(value) for value in row)
            for row in conn.execute("SELECT source, target FROM edges")
        )
    except sqlite3.DatabaseError as e:
        pytest.fail(f"{DB_PATH} is not a usable SQLite database: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

    expected_nodes = sorted(tuple(str(value) for value in row) for row in nodes)
    expected_edges = sorted(tuple(str(value) for value in row) for row in edges)
    assert actual_nodes == expected_nodes, "nodes table does not match nodes.csv"
    assert actual_edges == expected_edges, "edges table does not match edges.csv"


@pytest.fixture(scope="session", autouse=True)
def run_script():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Script path is not a regular file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    for path in (DB_PATH, JSON_PATH):
        if os.path.lexists(path):
            os.remove(path)
    execute_script()


def test_script_uses_sqlite_and_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    non_comment_source = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bsqlite3\b", non_comment_source, re.IGNORECASE), (
        "Script does not invoke sqlite3"
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", non_comment_source, re.IGNORECASE), (
        "Script does not contain a SQLite recursive CTE"
    )


def test_database_created():
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"


def test_database_materialization():
    nodes = [
        ("P001", "Graph Processing Basics", "2020"),
        ("P002", "Advanced SQL", "2019"),
        ("P003", "Data Querying Patterns", "2018"),
        ("P004", "Recursive CTEs in Practice", "2015"),
        ("P005", "Irrelevant Paper", "2021"),
        ("P006", "Deep Graph Traversals", "2012"),
        ("P007", "Beyond Depth 3", "2010"),
    ]
    edges = [
        ("P001", "P002"),
        ("P001", "P003"),
        ("P002", "P004"),
        ("P004", "P006"),
        ("P005", "P001"),
        ("P006", "P007"),
    ]
    assert_database(nodes, edges)


def test_json_output_exists():
    assert os.path.exists(JSON_PATH), f"JSON output file not found at {JSON_PATH}"


def test_json_output_content():
    expected_data = [
        {"depth": 0, "paper_id": "P001", "title": "Graph Processing Basics"},
        {"depth": 1, "paper_id": "P002", "title": "Advanced SQL"},
        {"depth": 1, "paper_id": "P003", "title": "Data Querying Patterns"},
        {"depth": 2, "paper_id": "P004", "title": "Recursive CTEs in Practice"},
        {"depth": 3, "paper_id": "P006", "title": "Deep Graph Traversals"},
    ]
    assert_json_records(load_json(), expected_data)


def test_dynamic_csv_ingestion_and_traversal():
    with open(NODES_PATH, "rb") as f:
        original_nodes = f.read()
    with open(EDGES_PATH, "rb") as f:
        original_edges = f.read()

    token = secrets.token_hex(6)
    a, b, c, d, e, outside = [f"X{name}_{token}" for name in "ABCDEF"]
    nodes = [
        ("P001", f"Dynamic Root {token}", "2030"),
        (b, f"Second branch {token}", "2029"),
        (a, f"First branch {token}", "2028"),
        (c, f"Depth two {token}", "2027"),
        (d, f"Other depth two {token}", "2026"),
        (e, f"Depth three {token}", "2025"),
        (outside, f"Beyond limit {token}", "2024"),
        (f"UNRELATED_{token}", f"Unrelated {token}", "2023"),
    ]
    edges = [
        ("P001", b),
        ("P001", a),
        (a, c),
        (b, d),
        (c, e),
        (e, outside),
        (f"UNRELATED_{token}", "P001"),
    ]

    titles = {paper_id: title for paper_id, title, _ in nodes}
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)

    reached = [(0, "P001")]
    frontier = ["P001"]
    for depth in range(1, 4):
        next_frontier = []
        for source in frontier:
            next_frontier.extend(adjacency.get(source, []))
        reached.extend((depth, paper_id) for paper_id in next_frontier)
        frontier = next_frontier

    expected = [
        {"depth": depth, "paper_id": paper_id, "title": titles[paper_id]}
        for depth, paper_id in sorted(reached, key=lambda item: (item[0], item[1]))
    ]

    try:
        with open(NODES_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "title", "year"])
            writer.writerows(nodes)
        with open(EDGES_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["source", "target"])
            writer.writerows(edges)

        for path in (DB_PATH, JSON_PATH):
            if os.path.lexists(path):
                os.remove(path)

        execute_script()
        assert_database(nodes, edges)
        assert_json_records(load_json(), expected)
    finally:
        with open(NODES_PATH, "wb") as f:
            f.write(original_nodes)
        with open(EDGES_PATH, "wb") as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
