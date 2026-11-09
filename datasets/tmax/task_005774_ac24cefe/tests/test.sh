#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

JSON_PATH = "/home/user/lineage_export.json"
GO_FILE_PATH = "/home/user/export_lineage.go"
DB_PATH = "/home/user/lineage.db"
BINARY_PATH = "/tmp/export_lineage_test"


def load_export():
    assert os.path.exists(JSON_PATH), f"JSON export file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f"Failed to parse JSON from {JSON_PATH}: {e}")


def validate_exact(data, expected_nodes, expected_edges):
    assert isinstance(data, dict), "Top-level JSON value must be an object."
    assert "nodes" in data, "JSON output is missing the 'nodes' key."
    assert "edges" in data, "JSON output is missing the 'edges' key."
    assert set(data.keys()) == {"nodes", "edges"}, f"Unexpected top-level keys: {set(data.keys())}"

    actual_nodes = data["nodes"]
    assert isinstance(actual_nodes, list), "'nodes' must be an array."
    for node in actual_nodes:
        assert "id" in node, f"Node missing 'id': {node}"
        assert "title" in node, f"Node missing 'title': {node}"
        assert "format" in node, f"Node missing 'format': {node}"
        assert set(node.keys()) == {"id", "title", "format"}, f"Node has incorrect keys: {node}"

    actual_node_ids = {n["id"] for n in actual_nodes}
    expected_node_ids = {n["id"] for n in expected_nodes}
    assert actual_node_ids == expected_node_ids, f"Node ID mismatch. Expected {expected_node_ids}, got {actual_node_ids}"
    assert len(actual_nodes) == len(expected_nodes), "Duplicate or extra nodes were exported."
    actual_node_values = {(n["id"], n["title"], n["format"]) for n in actual_nodes}
    expected_node_values = {(n["id"], n["title"], n["format"]) for n in expected_nodes}
    assert actual_node_values == expected_node_values, f"Node value mismatch. Expected {expected_node_values}, got {actual_node_values}"

    actual_edges_list = data["edges"]
    assert isinstance(actual_edges_list, list), "'edges' must be an array."
    for edge in actual_edges_list:
        assert "source" in edge, f"Edge missing 'source': {edge}"
        assert "target" in edge, f"Edge missing 'target': {edge}"
        assert "operation" in edge, f"Edge missing 'operation': {edge}"
        assert set(edge.keys()) == {"source", "target", "operation"}, f"Edge has incorrect keys: {edge}"

    actual_edges = {(e["source"], e["target"], e["operation"]) for e in actual_edges_list}
    assert actual_edges == expected_edges, f"Edge mismatch. Expected {expected_edges}, got {actual_edges}"
    assert len(actual_edges_list) == len(expected_edges), "Duplicate or extra edges were exported."


def run_export(start):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        [BINARY_PATH, "-start", str(start)],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Exporter failed for -start {start}. stdout={result.stdout!r} stderr={result.stderr!r}"
    return load_export()


def test_complete_submission():
    # Preserve the original verifier's existence and start-1 export assertions.
    assert os.path.exists(GO_FILE_PATH), f"Go source file {GO_FILE_PATH} does not exist."
    assert os.path.isfile(GO_FILE_PATH), f"{GO_FILE_PATH} is not a file."
    initial = load_export()
    original_nodes = [
        {"id": 1, "title": "Raw Sensor Data", "format": "csv"},
        {"id": 2, "title": "Cleaned Sensor Data", "format": "parquet"},
        {"id": 3, "title": "Aggregated Daily Data", "format": "json"},
        {"id": 4, "title": "Anomaly Report", "format": "pdf"},
        {"id": 7, "title": "Joined Analytics", "format": "parquet"},
    ]
    original_edges = {
        (1, 2, "clean"),
        (2, 3, "aggregate"),
        (3, 4, "detect_anomalies"),
        (3, 7, "join"),
    }
    validate_exact(initial, original_nodes, original_edges)

    with open(GO_FILE_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    recursive = re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE)
    assert recursive, "Go source does not contain a recursive SQL CTE."
    query_region = source[recursive.start():recursive.start() + 5000]
    assert re.search(r"\?|(?:[:@$][A-Za-z_][A-Za-z0-9_]*)", query_region), "Recursive CTE does not contain a SQL parameter placeholder."
    assert re.search(r"\.(?:Query|QueryContext)\s*\([^;]{0,800},", source, re.DOTALL), "No parameter argument is supplied to a SQL query call."

    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_FILE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert build.returncode == 0, f"Go program does not compile. stdout={build.stdout!r} stderr={build.stderr!r}"

    db_backup = "/tmp/lineage.db.verifier-backup"
    json_backup = "/tmp/lineage_export.json.verifier-backup"
    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(JSON_PATH, json_backup)
    try:
        # Exercise a different start ID on the supplied database.
        start5_nodes = [
            {"id": 5, "title": "User Logs", "format": "txt"},
            {"id": 6, "title": "Parsed Logs", "format": "csv"},
            {"id": 7, "title": "Joined Analytics", "format": "parquet"},
        ]
        start5_edges = {(5, 6, "parse"), (6, 7, "join")}
        validate_exact(run_export(5), start5_nodes, start5_edges)

        # Replace the fixed-path database with an unpredictable equivalent schema
        # and data set, ensuring the executable actually inspects SQLite and follows
        # the requested start value rather than emitting a canned graph.
        os.remove(DB_PATH)
        token = secrets.token_hex(4)
        dataset_table = f"dataset_inventory_{token}"
        edge_table = f"derivation_links_{token}"
        id_col = f"dataset_id_{token}"
        title_col = f"dataset_title_{token}"
        format_col = f"dataset_format_{token}"
        source_col = f"source_id_{token}"
        target_col = f"target_id_{token}"
        operation_col = f"operation_type_{token}"

        base = secrets.randbelow(500000) + 10000
        start, child, grandchild, terminal, outsider, other_child = [base + n * 17 for n in range(6)]
        nodes = [
            (start, f"Raw '{token}'", "binary/csv"),
            (child, f"Clean {token}", "columnar"),
            (grandchild, f"Aggregate {token}", "application/json"),
            (terminal, f"Report {token}", "application/pdf"),
            (outsider, f"Unrelated {token}", "text/plain"),
            (other_child, f"Outside child {token}", "archive"),
        ]
        edges = [
            (start, child, f"clean_{token}"),
            (child, grandchild, f"aggregate_{token}"),
            (grandchild, terminal, f"publish_{token}"),
            (outsider, other_child, f"parse_{token}"),
            (other_child, terminal, f"join_{token}"),
        ]

        con = sqlite3.connect(DB_PATH)
        try:
            con.execute(f'CREATE TABLE "{dataset_table}" ("{id_col}" INTEGER PRIMARY KEY, "{title_col}" TEXT, "{format_col}" TEXT)')
            con.execute(
                f'CREATE TABLE "{edge_table}" ('
                f'"{source_col}" INTEGER, "{target_col}" INTEGER, "{operation_col}" TEXT, '
                f'FOREIGN KEY("{source_col}") REFERENCES "{dataset_table}"("{id_col}"), '
                f'FOREIGN KEY("{target_col}") REFERENCES "{dataset_table}"("{id_col}"))'
            )
            con.executemany(f'INSERT INTO "{dataset_table}" VALUES (?, ?, ?)', nodes)
            con.executemany(f'INSERT INTO "{edge_table}" VALUES (?, ?, ?)', edges)
            con.commit()
        finally:
            con.close()

        expected_nodes = [
            {"id": start, "title": nodes[0][1], "format": nodes[0][2]},
            {"id": child, "title": nodes[1][1], "format": nodes[1][2]},
            {"id": grandchild, "title": nodes[2][1], "format": nodes[2][2]},
            {"id": terminal, "title": nodes[3][1], "format": nodes[3][2]},
        ]
        expected_edges = {
            (start, child, edges[0][2]),
            (child, grandchild, edges[1][2]),
            (grandchild, terminal, edges[2][2]),
        }
        validate_exact(run_export(start), expected_nodes, expected_edges)
    finally:
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(json_backup, JSON_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi
