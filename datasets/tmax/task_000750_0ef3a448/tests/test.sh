#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import sqlite3
import stat
import subprocess

import networkx as nx
import pytest

DB_PATH = "/home/user/network.db"
REPORT_PATH = "/home/user/report.json"
SCRIPT_PATH = "/home/user/analyze.py"

ORIGINAL_NODES = [
    (1, "Alpha"),
    (2, "Bravo"),
    (3, "Charlie"),
    (4, "Delta"),
    (5, "Echo Hub"),
]
ORIGINAL_EDGES = [
    (1, 5, 1.0),
    (2, 5, 2.0),
    (3, 5, 1.5),
    (4, 5, 0.5),
    (5, 1, 1.0),
    (2, 1, 1.0),
    (3, 1, 0.5),
]


def read_graph(db_path):
    conn = sqlite3.connect(db_path)
    try:
        nodes = conn.execute(
            "SELECT node_id, node_name FROM nodes ORDER BY node_id"
        ).fetchall()
        edges = conn.execute(
            "SELECT source, target, weight FROM edges ORDER BY rowid"
        ).fetchall()
        return nodes, edges
    finally:
        conn.close()


def expected_report(db_path):
    nodes, edges = read_graph(db_path)
    graph = nx.DiGraph()
    graph.add_nodes_from(node_id for node_id, _ in nodes)
    graph.add_weighted_edges_from(edges)
    scores = nx.pagerank(graph, weight="weight")
    names = {node_id: node_name for node_id, node_name in nodes}
    return names, scores


def validate_report(db_path, require_original_names=False):
    assert os.path.exists(REPORT_PATH), f"Report file missing: {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    assert isinstance(data, list), "The JSON root must be a list of objects."
    assert len(data) == 3, f"Expected exactly 3 items in report.json, found {len(data)}."

    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} must be an object."
        assert "node_name" in item, f"Item at index {i} is missing 'node_name'."
        assert "pagerank" in item, f"Item at index {i} is missing 'pagerank'."
        assert set(item) == {"node_name", "pagerank"}, \
            f"Item at index {i} must contain exactly node_name and pagerank."
        assert isinstance(item["node_name"], str), f"'node_name' at index {i} must be a string."
        assert isinstance(item["pagerank"], (int, float)) and not isinstance(item["pagerank"], bool), \
            f"'pagerank' at index {i} must be a number."
        assert math.isfinite(item["pagerank"]), f"'pagerank' at index {i} must be finite."

    assert data[0]["pagerank"] >= data[1]["pagerank"], \
        "PageRank values are not sorted in descending order."
    assert data[1]["pagerank"] >= data[2]["pagerank"], \
        "PageRank values are not sorted in descending order."

    names, scores = expected_report(db_path)
    score_by_name = {names[node_id]: round(score, 4) for node_id, score in scores.items()}
    expected_top_values = sorted(score_by_name.values(), reverse=True)[:3]

    reported_names = [item["node_name"] for item in data]
    assert len(set(reported_names)) == 3, "The report must contain three distinct nodes."
    assert sorted((item["pagerank"] for item in data), reverse=True) == expected_top_values, \
        "The report does not contain the correctly rounded top three PageRank values."

    for i, item in enumerate(data):
        name = item["node_name"]
        assert name in score_by_name, f"Unknown node name at index {i}: {name!r}."
        assert item["pagerank"] == score_by_name[name], \
            f"Incorrect four-decimal PageRank for node {name!r}: expected {score_by_name[name]}."

    if require_original_names:
        # Preserve the original verifier's assertions for the known graph.
        assert data[0]["node_name"] == "Echo Hub", \
            f"Expected top node to be 'Echo Hub', got '{data[0]['node_name']}'."
        assert data[1]["node_name"] == "Alpha", \
            f"Expected second node to be 'Alpha', got '{data[1]['node_name']}'."


def run_analysis():
    assert os.path.lexists(SCRIPT_PATH), f"Analysis script missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "analyze.py must be a regular Python file, not a symlink."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "analyze.py must be a regular file."
    assert os.path.getsize(SCRIPT_PATH) > 0, "analyze.py is empty."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"analyze.py failed with exit code {result.returncode}:\n{result.stderr}"
    assert os.path.exists(REPORT_PATH), "analyze.py did not generate report.json."


def assert_original_data():
    nodes, edges = read_graph(DB_PATH)
    assert nodes == ORIGINAL_NODES, "The data in the nodes table was modified."
    assert edges == ORIGINAL_EDGES, "The data in the edges table was modified."

    conn = sqlite3.connect(DB_PATH)
    try:
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        ).fetchall()
        assert tables == [("edges",), ("nodes",)], \
            "Only indexes may be added; database tables must not be added, removed, or renamed."
        assert conn.execute("PRAGMA table_info(nodes)").fetchall() == [
            (0, "node_id", "INTEGER", 0, None, 1),
            (1, "node_name", "TEXT", 0, None, 0),
        ], "The nodes schema was modified."
        assert conn.execute("PRAGMA table_info(edges)").fetchall() == [
            (0, "source", "INTEGER", 0, None, 0),
            (1, "target", "INTEGER", 0, None, 0),
            (2, "weight", "REAL", 0, None, 0),
        ], "The edges schema was modified."
        other_schema = conn.execute(
            "SELECT type, name FROM sqlite_master "
            "WHERE type IN ('view', 'trigger') ORDER BY type, name"
        ).fetchall()
        assert other_schema == [], "Only indexes may be added to the database schema."
    finally:
        conn.close()


def remove_sidecars(path):
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = path + suffix
        if os.path.exists(sidecar):
            os.remove(sidecar)


def create_alternate_database(path):
    remove_sidecars(path)
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    try:
        conn.executescript("""
            CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, node_name TEXT);
            CREATE TABLE edges (source INTEGER, target INTEGER, weight REAL);
            INSERT INTO nodes VALUES
                (10, 'Red'), (20, 'Blue'), (30, 'Green'),
                (40, 'Yellow'), (50, 'Purple'), (60, 'Gray');
            INSERT INTO edges VALUES
                (10, 20, 5.0), (30, 20, 2.0), (20, 30, 1.0),
                (40, 30, 4.0), (30, 40, 1.0), (50, 40, 3.0),
                (40, 50, 0.2), (20, 50, 0.4), (50, 10, 0.1);
        """)
        conn.commit()
    finally:
        conn.close()


def test_indexes_created():
    assert os.path.exists(DB_PATH), f"Database file missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges';")
        indexes = cursor.fetchall()
        assert len(indexes) > 0, "No indexes were created on the 'edges' table."

        indexed_columns = set()
        usable_index_names = set()
        for (idx_name,) in indexes:
            cursor.execute(f'PRAGMA index_info("{idx_name}");')
            info = cursor.fetchall()
            for col_info in info:
                col_name = col_info[2]
                if col_name:
                    indexed_columns.add(col_name)
            if info and info[0][2] in ("source", "target"):
                usable_index_names.add(idx_name)

        assert 'source' in indexed_columns or 'target' in indexed_columns, \
            "Expected an index on 'source' or 'target' columns of the 'edges' table to optimize the query."
        assert usable_index_names, \
            "An edges index must have source or target as its leading column for the join lookup."

        cursor.execute("PRAGMA automatic_index=OFF")
        plan = cursor.execute("""
            EXPLAIN QUERY PLAN
            SELECT e1.source, e2.target, SUM(e1.weight * e2.weight) AS two_hop_weight
            FROM edges e1
            JOIN edges e2 ON e1.target = e2.source
            GROUP BY e1.source, e2.target
        """).fetchall()
        plan_text = "\n".join(str(row[3]) for row in plan)
        assert any(name in plan_text and "SEARCH" in line.upper()
                   for name in usable_index_names for line in plan_text.splitlines()), \
            f"The self-join query plan does not use a created index for a lookup:\n{plan_text}"
    finally:
        conn.close()


def test_report_json_correctness_and_pipeline():
    assert_original_data()

    # Generate and validate the required report from the supplied database.
    run_analysis()
    assert_original_data()
    validate_report(DB_PATH, require_original_names=True)

    backup = "/tmp/network-original.db"
    remove_sidecars(DB_PATH)
    shutil.copy2(DB_PATH, backup)

    try:
        # Exercise the submitted pipeline on a different graph so a hardcoded report cannot pass.
        create_alternate_database(DB_PATH)
        alternate_before = read_graph(DB_PATH)
        run_analysis()
        assert read_graph(DB_PATH) == alternate_before, \
            "analyze.py modified table data while processing the alternate graph."
        validate_report(DB_PATH)
    finally:
        remove_sidecars(DB_PATH)
        shutil.copy2(backup, DB_PATH)
        remove_sidecars(DB_PATH)

    # Leave the requested report corresponding to the original database.
    run_analysis()
    assert_original_data()
    validate_report(DB_PATH, require_original_names=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
