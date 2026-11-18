#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import shutil
import sqlite3
import tempfile
import time
import heapq
from collections import Counter, defaultdict

import cv2
import pytest
from pyzbar.pyzbar import decode

DB_PATH = "/home/user/etl_graph.db"
ANALYZE_SCRIPT = "/home/user/analyze.py"
VIDEO_PATH = "/app/etl_monitor.mp4"
REQUIRED_COLUMNS = {"tx_id", "source", "target", "duration_ms"}


def qident(name):
    return '"' + name.replace('"', '""') + '"'


def extract_truth_data():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video: {VIDEO_PATH}"
    edges = []
    seen = set()
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        for obj in decode(frame):
            data = obj.data.decode("utf-8")
            if data not in seen:
                seen.add(data)
                edges.append(json.loads(data))
    cap.release()
    assert edges, "No QR-code edges could be extracted from the video"
    return edges


TRUTH_EDGES = extract_truth_data()


def load_analyze():
    spec = importlib.util.spec_from_file_location("submitted_analyze", ANALYZE_SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ANALYZE = None


def get_analyze():
    global ANALYZE
    if ANALYZE is None:
        ANALYZE = load_analyze()
    return ANALYZE


def find_edge_table(conn):
    tables = [row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )]
    matches = []
    for table in tables:
        columns = {
            row[1].lower(): row[1]
            for row in conn.execute(f"PRAGMA table_info({qident(table)})")
        }
        if REQUIRED_COLUMNS.issubset(columns):
            matches.append((table, columns))
    assert len(matches) == 1, (
        "Database must contain exactly one edge table with tx_id, source, target, "
        f"and duration_ms columns; found {[m[0] for m in matches]}"
    )
    return matches[0]


def get_truth_deadlocks(edges):
    graphs = defaultdict(list)
    for edge in edges:
        graphs[edge["tx_id"]].append((edge["source"], edge["target"]))

    deadlocks = []
    for tx_id, edge_list in graphs.items():
        adjacency = defaultdict(list)
        for source, target in edge_list:
            adjacency[source].append(target)

        visited = set()
        active = set()

        def cyclic(node):
            visited.add(node)
            active.add(node)
            for neighbor in adjacency[node]:
                if neighbor not in visited:
                    if cyclic(neighbor):
                        return True
                elif neighbor in active:
                    return True
            active.remove(node)
            return False

        if any(cyclic(node) for node in list(adjacency) if node not in visited):
            deadlocks.append(tx_id)
    return sorted(deadlocks)


def get_truth_shortest_path_func(edges):
    graphs = defaultdict(lambda: defaultdict(list))
    for edge in edges:
        graphs[edge["tx_id"]][edge["source"]].append(
            (edge["target"], edge["duration_ms"])
        )

    def shortest_path(tx_id, source, target):
        adjacency = graphs[tx_id]
        queue = [(0, source)]
        distances = {source: 0}
        while queue:
            distance, node = heapq.heappop(queue)
            if distance > distances.get(node, float("inf")):
                continue
            if node == target:
                return distance
            for neighbor, weight in adjacency[node]:
                candidate = distance + weight
                if candidate < distances.get(neighbor, float("inf")):
                    distances[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))
        return -1

    return shortest_path


def test_artifacts_and_database_contents():
    assert os.path.isfile(ANALYZE_SCRIPT), f"Missing script: {ANALYZE_SCRIPT}"
    assert os.path.isfile(DB_PATH), f"Missing database: {DB_PATH}"

    with open(DB_PATH, "rb") as database_file:
        assert database_file.read(16) == b"SQLite format 3\x00", "Database is not SQLite"

    with sqlite3.connect(DB_PATH) as conn:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        table, columns = find_edge_table(conn)
        selected = [columns[name] for name in ("tx_id", "source", "target", "duration_ms")]
        rows = conn.execute(
            f"SELECT {', '.join(qident(column) for column in selected)} "
            f"FROM {qident(table)}"
        ).fetchall()

        expected = Counter(
            (edge["tx_id"], edge["source"], edge["target"], edge["duration_ms"])
            for edge in TRUTH_EDGES
        )
        assert Counter(rows) == expected, "Database edges do not match the unique QR payloads"

        suitable_index = False
        for index_row in conn.execute(f"PRAGMA index_list({qident(table)})"):
            index_name = index_row[1]
            index_columns = [
                row[2].lower()
                for row in conn.execute(f"PRAGMA index_info({qident(index_name)})")
                if row[2] is not None
            ]
            if index_columns[:2] == ["tx_id", "source"]:
                suitable_index = True
                break
        assert suitable_index, (
            "Edge table needs an index beginning with (tx_id, source) for per-transaction traversal"
        )


def test_deadlocks_correctness():
    actual = get_analyze().find_deadlocks(DB_PATH)
    expected = get_truth_deadlocks(TRUTH_EDGES)
    assert actual == expected, f"Deadlocks mismatch. Expected {expected}, got {actual}"


def test_functions_use_supplied_database_path():
    analyze = get_analyze()
    direct_edge = next(edge for edge in TRUTH_EDGES if edge["source"] != edge["target"])

    with tempfile.TemporaryDirectory() as directory:
        alternate_db = os.path.join(directory, "empty_graph.db")
        shutil.copy2(DB_PATH, alternate_db)
        with sqlite3.connect(alternate_db) as conn:
            table, _ = find_edge_table(conn)
            conn.execute(f"DELETE FROM {qident(table)}")
            conn.commit()

        assert analyze.find_deadlocks(alternate_db) == [], (
            "find_deadlocks did not analyze the database supplied in db_path"
        )
        actual = analyze.get_shortest_path_duration(
            alternate_db,
            direct_edge["tx_id"],
            direct_edge["source"],
            direct_edge["target"],
        )
        assert actual == -1, (
            "get_shortest_path_duration did not analyze the database supplied in db_path"
        )


def test_shortest_path_benchmark_and_all_results():
    analyze = get_analyze()
    truth_shortest_path = get_truth_shortest_path_func(TRUTH_EDGES)

    nodes_per_tx = defaultdict(set)
    for edge in TRUTH_EDGES:
        nodes_per_tx[edge["tx_id"]].add(edge["source"])
        nodes_per_tx[edge["tx_id"]].add(edge["target"])
    nodes_per_tx = {tx: sorted(nodes) for tx, nodes in nodes_per_tx.items()}
    tx_ids = sorted(nodes_per_tx)

    random.seed(42)
    queries = []
    for _ in range(5000):
        tx_id = random.choice(tx_ids)
        source = random.choice(nodes_per_tx[tx_id])
        target = random.choice(nodes_per_tx[tx_id])
        queries.append((tx_id, source, target))

    expected_results = [truth_shortest_path(*query) for query in queries]

    # Preserve the original correctness assertions and cache warm-up.
    for query, expected in zip(queries[:50], expected_results[:50]):
        actual = analyze.get_shortest_path_duration(DB_PATH, *query)
        assert actual == expected, (
            f"Shortest path mismatch for {query}. Expected {expected}, got {actual}"
        )

    start_time = time.time()
    actual_results = [
        analyze.get_shortest_path_duration(DB_PATH, *query) for query in queries
    ]
    duration = time.time() - start_time

    for query, expected, actual in zip(queries, expected_results, actual_results):
        assert actual == expected, (
            f"Shortest path mismatch for {query}. Expected {expected}, got {actual}"
        )
    assert duration < 1.5, (
        f"Benchmark failed: took {duration:.3f} seconds, expected < 1.5 seconds. "
        "Check your database indexing."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
