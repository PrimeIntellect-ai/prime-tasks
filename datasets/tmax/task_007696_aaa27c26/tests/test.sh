#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import sqlite3
import pytest

EDGES_CSV_PATH = "/home/user/edges.csv"
TOP_AUTHORS_JSON_PATH = "/home/user/top_authors.json"
DB_PATH = "/home/user/research_data.db"


def expected_edges_from_database():
    assert os.path.isfile(DB_PATH), f"Database missing at {DB_PATH}"
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        # Ensure the source database used for verification was not replaced or altered.
        authors = conn.execute(
            "SELECT author_id, name FROM authors ORDER BY author_id"
        ).fetchall()
        papers = conn.execute(
            "SELECT paper_id, title FROM papers ORDER BY paper_id"
        ).fetchall()
        relations = conn.execute(
            "SELECT paper_id, author_id FROM paper_authors ORDER BY paper_id, author_id"
        ).fetchall()

        assert authors == [
            (1, "Alice Smith"),
            (2, "Bob Jones"),
            (3, "Charlie Brown"),
            (4, "David Clark"),
            (5, "Eve Davis"),
            (6, "Frank White"),
        ], "The authors table was altered."
        assert papers == [
            (101, "Quantum AI"),
            (102, "Neural Networks"),
            (103, "Graph Databases"),
        ], "The papers table was altered."
        assert relations == [
            (101, 1), (101, 2), (101, 3),
            (102, 1), (102, 4), (102, 5),
            (103, 2), (103, 6),
        ], "The paper_authors table was altered."

        rows = conn.execute("""
            SELECT DISTINCT a1.name, a2.name
            FROM paper_authors AS pa1
            JOIN paper_authors AS pa2
              ON pa1.paper_id = pa2.paper_id
             AND pa1.author_id < pa2.author_id
            JOIN authors AS a1 ON a1.author_id = pa1.author_id
            JOIN authors AS a2 ON a2.author_id = pa2.author_id
        """).fetchall()
        return {tuple(sorted((name1, name2))) for name1, name2 in rows}
    finally:
        conn.close()


def read_submitted_edges():
    with open(EDGES_CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader)
        return {
            tuple(sorted((row[0].strip(), row[1].strip())))
            for row in reader if row
        }


def test_edges_csv_exists_and_format():
    assert os.path.exists(EDGES_CSV_PATH), f"Edges file missing at {EDGES_CSV_PATH}"
    assert os.path.isfile(EDGES_CSV_PATH), f"Expected a file at {EDGES_CSV_PATH}"

    with open(EDGES_CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{EDGES_CSV_PATH} is empty.")

        # Header should be author1,author2
        assert [h.strip() for h in header] == ["author1", "author2"], \
            f"Expected header ['author1', 'author2'], found {header}"

        edges = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Expected 2 columns in row, found {len(row)}: {row}"
            u, v = row[0].strip(), row[1].strip()
            assert u != v, f"Self-loop found in edges: {u} - {v}"
            # Store as a canonical sorted tuple to ignore direction
            edges.append(tuple(sorted([u, v])))

    # Check for duplicates
    unique_edges = set(edges)
    assert len(edges) == len(unique_edges), "Duplicate edges found in the CSV (graph should be unweighted/undirected)."

    # There should be exactly 7 unique edges based on the setup
    assert len(unique_edges) == 7, f"Expected exactly 7 edges, found {len(unique_edges)}"

    expected_edges = expected_edges_from_database()
    assert unique_edges == expected_edges, \
        f"CSV edges do not match the co-authorship relationships in the database. Missing: {sorted(expected_edges - unique_edges)}; unexpected: {sorted(unique_edges - expected_edges)}"


def test_top_authors_json():
    assert os.path.exists(TOP_AUTHORS_JSON_PATH), f"JSON file missing at {TOP_AUTHORS_JSON_PATH}"
    assert os.path.isfile(TOP_AUTHORS_JSON_PATH), f"Expected a file at {TOP_AUTHORS_JSON_PATH}"

    with open(TOP_AUTHORS_JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Invalid JSON in {TOP_AUTHORS_JSON_PATH}: {e}")

    assert isinstance(data, list), f"Expected JSON root to be a list, found {type(data).__name__}"
    assert len(data) == 3, f"Expected exactly 3 top authors, found {len(data)}"

    expected = [
        {"name": "Alice Smith", "centrality": 0.8},
        {"name": "Bob Jones", "centrality": 0.6},
        {"name": "Charlie Brown", "centrality": 0.4}
    ]

    for i, (actual_item, expected_item) in enumerate(zip(data, expected)):
        assert isinstance(actual_item, dict), f"Item at index {i} is not a dictionary."
        assert "name" in actual_item, f"Missing 'name' key in item at index {i}."
        assert "centrality" in actual_item, f"Missing 'centrality' key in item at index {i}."

        actual_name = actual_item["name"]
        expected_name = expected_item["name"]
        assert actual_name == expected_name, \
            f"Rank {i+1} expected name '{expected_name}', found '{actual_name}'."

        actual_cent = actual_item["centrality"]
        expected_cent = expected_item["centrality"]
        assert isinstance(actual_cent, (int, float)), \
            f"Centrality for {actual_name} should be a number, found {type(actual_cent).__name__}."

        assert math.isclose(actual_cent, expected_cent, rel_tol=1e-3, abs_tol=1e-3), \
            f"Rank {i+1} expected centrality ~{expected_cent}, found {actual_cent}."


def test_json_matches_database_graph():
    edges = expected_edges_from_database()
    nodes = {node for edge in edges for node in edge}
    degrees = {node: 0 for node in nodes}
    for u, v in edges:
        degrees[u] += 1
        degrees[v] += 1

    denominator = len(nodes) - 1
    expected = sorted(
        (
            {"name": name, "centrality": round(degree / denominator, 4)}
            for name, degree in degrees.items()
        ),
        key=lambda item: (-item["centrality"], item["name"]),
    )[:3]

    with open(TOP_AUTHORS_JSON_PATH, 'r', encoding='utf-8') as f:
        actual = json.load(f)

    for index, (actual_item, expected_item) in enumerate(zip(actual, expected)):
        assert actual_item["name"] == expected_item["name"], \
            f"Database-derived rank {index + 1} should be {expected_item['name']}"
        assert math.isclose(
            actual_item["centrality"], expected_item["centrality"],
            rel_tol=1e-3, abs_tol=1e-3
        ), f"Centrality for {expected_item['name']} does not match the database graph."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
