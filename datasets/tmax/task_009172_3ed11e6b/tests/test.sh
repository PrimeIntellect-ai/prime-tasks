#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import runpy
import sqlite3
import sys

import networkx as nx
import pytest

DB_PATH = "/home/user/logistics.db"
GRAPH_SCRIPT_PATH = "/home/user/graph_analysis.py"
BOTTLENECK_PATH = "/home/user/bottleneck.txt"
QUERY_PATH = "/home/user/query.sql"
JSON_PATH = "/home/user/expensive_deliveries.json"


def expected_graph_and_bottleneck():
    conn = sqlite3.connect(DB_PATH)
    try:
        nodes = conn.execute("SELECT id, name FROM t1_x").fetchall()
        edges = conn.execute("SELECT source_id, target_id FROM t2_y").fetchall()
    finally:
        conn.close()

    graph = nx.Graph()
    graph.add_nodes_from(node_id for node_id, _ in nodes)
    graph.add_edges_from(edges)
    centrality = nx.betweenness_centrality(graph, weight=None)
    winner_id = max(centrality, key=centrality.get)
    names = dict(nodes)
    return graph, names[winner_id]


def expected_delivery_rows():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        query = """
        WITH ValidDeliveries AS (
            SELECT
                d.delivery_id,
                n1.region_code,
                d.cost,
                n1.name as source_name,
                n2.name as dest_name
            FROM t3_z d
            JOIN t1_x n1 ON d.src_id = n1.id
            JOIN t1_x n2 ON d.dst_id = n2.id
            JOIN t2_y e ON d.src_id = e.source_id AND d.dst_id = e.target_id
            WHERE e.distance > 100
        ),
        RankedDeliveries AS (
            SELECT *,
                   ROW_NUMBER() OVER(PARTITION BY region_code ORDER BY cost DESC, delivery_id ASC) as rn
            FROM ValidDeliveries
        )
        SELECT delivery_id, region_code, cost, source_name, dest_name
        FROM RankedDeliveries
        WHERE rn <= 2
        ORDER BY region_code ASC, cost DESC
        """
        return [dict(row) for row in conn.execute(query).fetchall()]
    finally:
        conn.close()


def assert_rows_match(actual_rows, expected_rows, prefix=""):
    assert len(actual_rows) == len(expected_rows), (
        f"{prefix}Expected {len(expected_rows)} deliveries, got {len(actual_rows)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual.get("delivery_id") == expected["delivery_id"], f"{prefix}Row {i}: Expected delivery_id {expected['delivery_id']}, got {actual.get('delivery_id')}"
        assert actual.get("region_code") == expected["region_code"], f"{prefix}Row {i}: Expected region_code {expected['region_code']}, got {actual.get('region_code')}"
        assert float(actual.get("cost")) == float(expected["cost"]), f"{prefix}Row {i}: Expected cost {expected['cost']}, got {actual.get('cost')}"
        assert actual.get("source_name") == expected["source_name"], f"{prefix}Row {i}: Expected source_name {expected['source_name']}, got {actual.get('source_name')}"
        assert actual.get("dest_name") == expected["dest_name"], f"{prefix}Row {i}: Expected dest_name {expected['dest_name']}, got {actual.get('dest_name')}"


def test_graph_analysis_script_executes_networkx_analysis():
    assert os.path.isfile(GRAPH_SCRIPT_PATH), f"File missing: {GRAPH_SCRIPT_PATH}"

    expected_graph, expected_bottleneck = expected_graph_and_bottleneck()
    original_connect = sqlite3.connect
    original_bc = nx.betweenness_centrality
    import networkx.algorithms.centrality as nx_centrality
    import networkx.algorithms.centrality.betweenness as nx_betweenness

    original_centrality_bc = nx_centrality.betweenness_centrality
    original_module_bc = nx_betweenness.betweenness_centrality
    database_opened = []
    analyzed_graphs = []

    def monitored_connect(database, *args, **kwargs):
        raw = os.fspath(database)
        normalized = raw
        if normalized.startswith("file:"):
            normalized = normalized[5:].split("?", 1)[0]
        if os.path.realpath(normalized) == os.path.realpath(DB_PATH):
            database_opened.append(True)
        return original_connect(database, *args, **kwargs)

    def monitored_betweenness(graph, *args, **kwargs):
        analyzed_graphs.append(graph.copy())
        return original_bc(graph, *args, **kwargs)

    old_cwd = os.getcwd()
    old_argv = sys.argv[:]
    sqlite3.connect = monitored_connect
    nx.betweenness_centrality = monitored_betweenness
    nx_centrality.betweenness_centrality = monitored_betweenness
    nx_betweenness.betweenness_centrality = monitored_betweenness
    try:
        os.chdir("/home/user")
        sys.argv = [GRAPH_SCRIPT_PATH]
        runpy.run_path(GRAPH_SCRIPT_PATH, run_name="__main__")
    finally:
        os.chdir(old_cwd)
        sys.argv = old_argv
        sqlite3.connect = original_connect
        nx.betweenness_centrality = original_bc
        nx_centrality.betweenness_centrality = original_centrality_bc
        nx_betweenness.betweenness_centrality = original_module_bc

    assert database_opened, "graph_analysis.py did not open logistics.db"
    assert analyzed_graphs, "graph_analysis.py did not call networkx.betweenness_centrality"
    assert any(
        len(g.nodes) == len(expected_graph.nodes)
        and len(nx.Graph(g).edges) == len(expected_graph.edges)
        and nx.is_isomorphic(nx.Graph(g), expected_graph)
        for g in analyzed_graphs
    ), "NetworkX betweenness centrality was not run on the graph represented by the database"
    assert os.path.exists(BOTTLENECK_PATH), f"File missing after executing script: {BOTTLENECK_PATH}"
    with open(BOTTLENECK_PATH, "r") as f:
        assert f.read().strip() == expected_bottleneck


def test_bottleneck_file():
    assert os.path.exists(BOTTLENECK_PATH), f"File missing: {BOTTLENECK_PATH}"
    with open(BOTTLENECK_PATH, "r") as f:
        content = f.read().strip()
    assert content == "Central_Sort", f"Expected bottleneck to be 'Central_Sort', but got '{content}'"


def test_sql_query_file():
    assert os.path.exists(QUERY_PATH), f"File missing: {QUERY_PATH}"
    with open(QUERY_PATH, "r") as f:
        submitted_query = f.read()

    content = submitted_query.upper()
    assert "OVER" in content or "WINDOW" in content, "The SQL query must use a Window Function (OVER or WINDOW clause)."

    # Do not count keywords hidden only in comments or string literals.
    executable_text = re.sub(
        r"--[^\n]*|/\*.*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"",
        " ",
        submitted_query,
        flags=re.DOTALL,
    )
    assert re.search(r"\bOVER\s*(?:\(|[A-Za-z_])", executable_text, re.IGNORECASE) or re.search(
        r"\bWINDOW\s+[A-Za-z_]\w*\s+AS\s*\(", executable_text, re.IGNORECASE
    ), "The executable SQL must contain a window-function OVER clause or named WINDOW clause."

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA query_only = ON")
        try:
            cursor = conn.execute(submitted_query)
            rows = cursor.fetchall()
        except sqlite3.Error as exc:
            pytest.fail(f"query.sql could not be executed against logistics.db: {exc}")
    finally:
        conn.close()

    expected_columns = ["delivery_id", "region_code", "cost", "source_name", "dest_name"]
    actual_columns = [column[0] for column in cursor.description] if cursor.description else []
    assert actual_columns == expected_columns, f"Expected query columns {expected_columns}, got {actual_columns}"
    actual_rows = [dict(row) for row in rows]
    assert_rows_match(actual_rows, expected_delivery_rows(), prefix="Submitted SQL: ")


def test_expensive_deliveries_json():
    assert os.path.exists(JSON_PATH), f"File missing: {JSON_PATH}"
    expected_rows = expected_delivery_rows()

    with open(JSON_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert isinstance(actual_data, list), f"Expected JSON to be a list, got {type(actual_data)}"
    assert_rows_match(actual_data, expected_rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
