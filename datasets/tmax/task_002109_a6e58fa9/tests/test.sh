#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import json
import csv
import heapq
from collections import Counter, defaultdict

import networkx as nx

DB_PATH = "/home/user/network.db"
CSV_PATH = "/home/user/routes.csv"
JSON_PATH = "/home/user/analysis_result.json"


def load_expected_data():
    assert os.path.exists(CSV_PATH), f"Missing {CSV_PATH} (needed for verification)"

    historical = []
    active = {}
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            item = (
                row["source"],
                row["target"],
                float(row["distance"]),
                float(row["last_updated"]),
            )
            historical.append(item)
            key = item[:2]
            if key not in active or active[key][3] < item[3]:
                active[key] = item

    return historical, active


def quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def test_network_db_exists():
    """Test that the database contains both loaded history and an SQL-derived active relation."""
    assert os.path.exists(DB_PATH), f"Missing {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file"

    historical, active = load_expected_data()
    expected_history = Counter(historical)
    expected_active = Counter(active.values())

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name, type FROM sqlite_master WHERE type='table' OR type='view';")
        relations = cursor.fetchall()
        assert len(relations) > 0, "Database is empty (no tables or views found)."

        history_matches = []
        active_matches = []

        for name, relation_type in relations:
            try:
                cursor.execute(f"PRAGMA table_info({quote_identifier(name)})")
                columns = cursor.fetchall()
                by_lower_name = {column[1].lower(): column[1] for column in columns}
                required = {"source", "target", "distance", "last_updated"}
                if not required.issubset(by_lower_name):
                    continue

                selected = [by_lower_name[key] for key in ("source", "target", "distance", "last_updated")]
                select_sql = ", ".join(quote_identifier(column) for column in selected)
                cursor.execute(f"SELECT {select_sql} FROM {quote_identifier(name)}")
                normalized = Counter(
                    (str(row[0]), str(row[1]), float(row[2]), float(row[3]))
                    for row in cursor.fetchall()
                )
                if normalized == expected_history:
                    history_matches.append((name, relation_type))
                if normalized == expected_active:
                    active_matches.append((name, relation_type))
            except (sqlite3.DatabaseError, TypeError, ValueError):
                continue

        assert history_matches, \
            "No database table/view contains all historical CSV rows; the CSV was not properly loaded."
        assert active_matches, \
            "No database table/view contains exactly the latest row for each (source, target) pair."
        assert {name for name, _ in history_matches} != {name for name, _ in active_matches}, \
            "The historical and active network must be represented by distinct database relations."
        conn.close()
    except sqlite3.DatabaseError as e:
        assert False, f"Failed to open {DB_PATH} as a SQLite database: {e}"


def test_analysis_result_content():
    """Test analysis_result.json by independently recomputing all requested metrics."""
    assert os.path.exists(JSON_PATH), f"Missing {JSON_PATH}"

    with open(JSON_PATH, "r") as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON format in {JSON_PATH}"

    _, edges = load_expected_data()

    expected_edge_count = len(edges)
    actual_edge_count = res.get("active_edge_count")
    assert actual_edge_count == expected_edge_count, \
        f"Edge count mismatch: expected {expected_edge_count}, got {actual_edge_count}"

    graph = defaultdict(list)
    for (u, v), data in edges.items():
        graph[u].append((v, data[2]))

    pq = [(0.0, "S", ["S"])]
    visited = set()
    shortest_path = None
    shortest_dist = None

    while pq:
        dist, node, path = heapq.heappop(pq)
        if node == "T":
            shortest_path = path
            shortest_dist = dist
            break
        if node in visited:
            continue
        visited.add(node)
        for neighbor, weight in graph[node]:
            if neighbor not in visited:
                heapq.heappush(pq, (dist + weight, neighbor, path + [neighbor]))

    actual_path = res.get("shortest_path_S_to_T")
    assert actual_path == shortest_path, \
        f"Shortest path mismatch: expected {shortest_path}, got {actual_path}"

    actual_dist = res.get("shortest_path_distance")
    assert actual_dist is not None, "Missing 'shortest_path_distance' in JSON"
    assert abs(float(actual_dist) - shortest_dist) < 1e-6, \
        f"Shortest path distance mismatch: expected {shortest_dist}, got {actual_dist}"

    nx_graph = nx.DiGraph()
    for u, v in edges:
        nx_graph.add_edge(u, v)
    centrality = nx.betweenness_centrality(nx_graph)
    expected_top_3 = [
        node for node, _ in sorted(centrality.items(), key=lambda item: (-item[1], item[0]))[:3]
    ]

    actual_top_3 = res.get("top_3_betweenness_nodes", [])
    assert actual_top_3 == expected_top_3, \
        f"Betweenness centrality top 3 mismatch: expected {expected_top_3}, got {actual_top_3}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
