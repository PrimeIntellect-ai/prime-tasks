#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import uuid
import pytest

DB_PATH = "/home/user/network.db"
SCRIPT_PATH = "/home/user/etl_pipeline.sh"
JSON_PATH = "/home/user/graph.json"
METRICS_PATH = "/home/user/metrics.txt"


def index_key_columns(conn):
    rows = conn.execute("PRAGMA index_xinfo('idx_source_weight')").fetchall()
    return [(row[2], row[3]) for row in rows if row[5] == 1]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script file {SCRIPT_PATH} is not executable."


def test_index_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('edges');")
    indexes = [row[1] for row in cursor.fetchall()]
    assert 'idx_source_weight' in indexes, "Index 'idx_source_weight' was not created on the 'edges' table."

    cursor.execute("PRAGMA index_info('idx_source_weight');")
    columns = [row[2] for row in cursor.fetchall()]
    assert 'source_id' in columns and 'weight' in columns, "Index 'idx_source_weight' does not cover the correct columns."
    assert index_key_columns(conn) == [('source_id', 0), ('weight', 1)], \
        "Index 'idx_source_weight' must index source_id followed by weight DESC."
    conn.close()


def test_top_edges_table():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='top_edges';")
    assert cursor.fetchone() is not None, "Table 'top_edges' is missing in the database."

    cursor.execute("SELECT source_id, target_id, weight FROM top_edges ORDER BY source_id, target_id;")
    actual_top_edges = cursor.fetchall()
    conn.close()

    expected_top_edges = [
        (1, 2, 10), (1, 4, 15),
        (2, 1, 8), (2, 4, 12),
        (3, 1, 20), (3, 5, 25),
        (4, 2, 5), (4, 5, 5)
    ]

    assert actual_top_edges == expected_top_edges, f"Data in 'top_edges' is incorrect. Expected {expected_top_edges}, got {actual_top_edges}"


def test_graph_json():
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    assert "nodes" in data, "JSON output missing 'nodes' key."
    assert "edges" in data, "JSON output missing 'edges' key."

    expected_nodes = [
        {"id": 1, "label": "Node1", "category": "Alpha"},
        {"id": 2, "label": "Node2", "category": "Alpha"},
        {"id": 3, "label": "Node3", "category": "Beta"},
        {"id": 4, "label": "Node4", "category": "Beta"},
        {"id": 5, "label": "Node5", "category": "Gamma"}
    ]

    expected_edges = [
        {"source": 1, "target": 2, "weight": 10},
        {"source": 1, "target": 4, "weight": 15},
        {"source": 2, "target": 1, "weight": 8},
        {"source": 2, "target": 4, "weight": 12},
        {"source": 3, "target": 1, "weight": 20},
        {"source": 3, "target": 5, "weight": 25},
        {"source": 4, "target": 2, "weight": 5},
        {"source": 4, "target": 5, "weight": 5}
    ]

    actual_nodes = sorted(data["nodes"], key=lambda x: x.get("id", 0))
    actual_edges = sorted(data["edges"], key=lambda x: (x.get("source", 0), x.get("target", 0)))

    assert actual_nodes == expected_nodes, "JSON 'nodes' data is incorrect."
    assert actual_edges == expected_edges, "JSON 'edges' data is incorrect."


def test_metrics_txt():
    assert os.path.isfile(METRICS_PATH), f"Metrics file {METRICS_PATH} is missing."

    with open(METRICS_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Category: Alpha, Total Weight: 68",
        "Category: Beta, Total Weight: 55"
    ]

    assert lines == expected_lines, f"Contents of {METRICS_PATH} are incorrect. Expected {expected_lines}, got {lines}"


def test_pipeline_executes_on_fresh_unseen_data():
    token = uuid.uuid4().hex[:10]
    categories = {
        1: f"Alpha_{token}",
        2: f"Alpha_{token}",
        3: f"Beta_{token}",
        4: f"Beta_{token}",
        5: f"Gamma_{token}",
    }
    nodes = [(i, f"Node_{i}_{token}", categories[i]) for i in range(1, 6)]

    # Preserve the original graph shape while changing which targets rank highest.
    shapes = {
        1: [2, 3, 4, 5],
        2: [1, 3, 4],
        3: [1, 5],
        4: [2, 5],
    }
    edges = []
    for source, targets in shapes.items():
        shuffled = list(targets)
        secrets.SystemRandom().shuffle(shuffled)
        base = secrets.randbelow(500) + 20
        if len(shuffled) >= 3:
            weights = [base + 30, base + 10, base + 10] + [base] * (len(shuffled) - 3)
        else:
            weights = [base + 7, base + 3]
        edges.extend((source, target, weight) for target, weight in zip(shuffled, weights))

    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", JSON_PATH, METRICS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, label TEXT, category TEXT);
        CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight INTEGER);
    """)
    conn.executemany("INSERT INTO nodes(node_id,label,category) VALUES (?,?,?)", nodes)
    conn.executemany("INSERT INTO edges(source_id,target_id,weight) VALUES (?,?,?)", edges)
    conn.commit()
    conn.close()

    result = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f"ETL script failed on a fresh database. stdout={result.stdout!r}, stderr={result.stderr!r}"

    expected_top = []
    for source in sorted(shapes):
        outgoing = [edge for edge in edges if edge[0] == source]
        expected_top.extend(sorted(outgoing, key=lambda row: (-row[2], row[1]))[:2])
    expected_top = sorted(expected_top, key=lambda row: (row[0], row[1]))

    conn = sqlite3.connect(DB_PATH)
    indexes = [row[1] for row in conn.execute("PRAGMA index_list('edges')")]
    assert 'idx_source_weight' in indexes
    assert index_key_columns(conn) == [('source_id', 0), ('weight', 1)], \
        "Index 'idx_source_weight' must index source_id followed by weight DESC."
    table = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='top_edges'").fetchone()
    assert table is not None, "The executed script did not create top_edges."
    actual_top = conn.execute(
        "SELECT source_id,target_id,weight FROM top_edges ORDER BY source_id,target_id"
    ).fetchall()
    conn.close()
    assert actual_top == expected_top

    assert os.path.isfile(JSON_PATH), "The executed script did not create graph.json."
    with open(JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)
    expected_nodes = [
        {"id": node_id, "label": label, "category": category}
        for node_id, label, category in nodes
    ]
    expected_json_edges = [
        {"source": source, "target": target, "weight": weight}
        for source, target, weight in expected_top
    ]
    assert sorted(data["nodes"], key=lambda row: row["id"]) == expected_nodes
    assert sorted(data["edges"], key=lambda row: (row["source"], row["target"])) == expected_json_edges

    totals = {}
    for source, _target, weight in edges:
        category = categories[source]
        totals[category] = totals.get(category, 0) + weight
    expected_metrics = [
        f"Category: {category}, Total Weight: {totals[category]}"
        for category in sorted(totals)
    ]
    assert os.path.isfile(METRICS_PATH), "The executed script did not create metrics.txt."
    with open(METRICS_PATH, encoding="utf-8") as f:
        actual_metrics = [line.strip() for line in f if line.strip()]
    assert actual_metrics == expected_metrics
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
