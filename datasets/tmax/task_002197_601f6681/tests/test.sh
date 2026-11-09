#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import csv
import json
import shutil
import secrets
import sqlite3
import tempfile
import subprocess
from collections import Counter, deque

import pytest

DB_PATH = "/home/user/network.db"
QUERY_PATH = "/home/user/fixed_query.sql"
CSV_PATH = "/home/user/recent_edges.csv"
SCRIPT_PATH = "/home/user/graph_analytics.py"
REPORT_PATH = "/home/user/report.json"
INDEXES_PATH = "/home/user/indexes.sql"
COLUMNS = ["source", "target", "weight", "timestamp", "region"]


def read_query():
    with open(QUERY_PATH, "r") as f:
        return f.read()


def expected_rows(conn):
    regions = dict(conn.execute("SELECT id, region FROM nodes"))
    latest = {}
    for source, target, weight, timestamp in conn.execute(
        "SELECT source, target, weight, timestamp FROM edges"
    ):
        if source not in regions or target not in regions:
            continue
        if regions[source] != regions[target]:
            continue
        key = (source, target)
        if key not in latest or timestamp > latest[key][1]:
            latest[key] = (weight, timestamp)
    return Counter(
        (source, target, value[0], value[1], regions[source])
        for (source, target), value in latest.items()
    )


def execute_query(conn, sql):
    cursor = conn.execute(sql)
    names = [description[0].lower() for description in cursor.description or []]
    assert names == COLUMNS, f"Query columns must be exactly {COLUMNS}, got {names}."
    return Counter(tuple(row) for row in cursor.fetchall())


def load_report():
    assert os.path.isfile(REPORT_PATH), "graph_analytics.py did not create report.json."
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON.")
    assert set(report) == {"shortest_path", "max_degree_node"}, \
        "report.json must contain exactly shortest_path and max_degree_node."
    return report


def expected_graph_values(rows):
    adjacency = {}
    for row in rows:
        source = int(row["source"])
        target = int(row["target"])
        adjacency.setdefault(source, set()).add(target)
        adjacency.setdefault(target, set()).add(source)

    distances = {1: 0}
    queue = deque([1])
    while queue:
        node = queue.popleft()
        for neighbor in adjacency.get(node, set()):
            if neighbor not in distances:
                distances[neighbor] = distances[node] + 1
                queue.append(neighbor)
    assert 5 in distances, "Verifier probe graph unexpectedly has no path from 1 to 5."

    max_degree = max(len(neighbors) for neighbors in adjacency.values())
    max_node = min(
        node for node, neighbors in adjacency.items() if len(neighbors) == max_degree
    )
    return adjacency, distances[5], max_node


def assert_graph_report(report, rows):
    adjacency, shortest_distance, max_node = expected_graph_values(rows)
    path = report.get("shortest_path")
    assert isinstance(path, list), "shortest_path must be a list."
    assert path and path[0] == 1 and path[-1] == 5, \
        "shortest_path must start at 1 and end at 5."
    assert all(isinstance(node, int) and not isinstance(node, bool) for node in path), \
        "shortest_path node IDs must be integers."
    assert len(path) - 1 == shortest_distance, "Reported path is not a shortest path."
    for left, right in zip(path, path[1:]):
        assert right in adjacency.get(left, set()), \
            f"Reported path uses nonexistent edge {left}-{right}."
    assert report.get("max_degree_node") == max_node, \
        f"Expected max_degree_node {max_node}, got {report.get('max_degree_node')}."


def run_graph_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"graph_analytics.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    return load_report()


def test_fixed_query_file():
    fixed_query_path = "/home/user/fixed_query.sql"
    assert os.path.isfile(fixed_query_path), f"File {fixed_query_path} does not exist."
    with open(fixed_query_path, 'r') as f:
        content = f.read().lower()
        assert "join" in content, "fixed_query.sql must use standard JOINs."
        assert "over" in content, "fixed_query.sql must use a Window Function (like ROW_NUMBER() OVER(...))."
    assert re.search(r"\bjoin\b", content), "fixed_query.sql must contain a JOIN."
    assert re.search(r"\bover\s*\(", content), "fixed_query.sql must contain a window OVER clause."

    sql = read_query()
    with sqlite3.connect(DB_PATH) as conn:
        assert execute_query(conn, sql) == expected_rows(conn), \
            "fixed_query.sql does not return the correct latest same-region edges."

    # Exercise the submitted query against a fresh randomized database so a
    # hardcoded result for network.db cannot pass.
    rng = secrets.SystemRandom()
    ids = rng.sample(range(100, 10000), 5)
    region_a = "R" + secrets.token_hex(5)
    region_b = "R" + secrets.token_hex(5)
    weights = rng.sample(range(10, 10000), 7)
    times = rng.sample(range(10000, 100000), 7)
    times[1] = max(times[0], times[1]) + 100000
    times[4] = max(times[3], times[4]) + 200000

    with sqlite3.connect(":memory:") as conn:
        conn.executescript("""
            CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
            CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER, timestamp INTEGER);
        """)
        conn.executemany(
            "INSERT INTO nodes VALUES (?, ?, ?)",
            [
                (ids[0], "n0", region_a), (ids[1], "n1", region_a),
                (ids[2], "n2", region_a), (ids[3], "n3", region_b),
                (ids[4], "n4", region_b),
            ],
        )
        conn.executemany(
            "INSERT INTO edges VALUES (?, ?, ?, ?)",
            [
                (ids[0], ids[1], weights[0], times[0]),
                (ids[0], ids[1], weights[1], times[1]),
                (ids[1], ids[2], weights[2], times[2]),
                (ids[3], ids[4], weights[3], times[3]),
                (ids[3], ids[4], weights[4], times[4]),
                (ids[0], ids[3], weights[5], times[5]),
                (ids[4], ids[2], weights[6], times[6]),
            ],
        )
        assert execute_query(conn, sql) == expected_rows(conn), \
            "fixed_query.sql failed on a fresh database with different data."


def test_indexes_applied():
    db_path = "/home/user/network.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA index_list('edges');")
    edges_indexes = cursor.fetchall()

    cursor.execute("PRAGMA index_list('nodes');")
    nodes_indexes = cursor.fetchall()

    assert len(edges_indexes) > 0 or len(nodes_indexes) > 0, "No indexes were applied to the edges or nodes tables."
    conn.close()

    indexes_path = "/home/user/indexes.sql"
    assert os.path.isfile(indexes_path), f"File {indexes_path} does not exist."
    with open(indexes_path, "r") as f:
        index_sql = f.read()
    assert re.search(r"\bcreate\s+(?:unique\s+)?index\b", index_sql, re.I), \
        "indexes.sql must contain CREATE INDEX statements."

    with sqlite3.connect(":memory:") as conn:
        conn.executescript("""
            CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
            CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER, timestamp INTEGER);
        """)
        conn.executescript(index_sql)
        created = conn.execute("PRAGMA index_list('edges')").fetchall()
        created += conn.execute("PRAGMA index_list('nodes')").fetchall()
        assert created, "Executing indexes.sql did not create an index on nodes or edges."


def test_recent_edges_csv():
    csv_path = "/home/user/recent_edges.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 6, f"Expected 6 rows in CSV, found {len(rows)}."

    # Check that cross-region edge is excluded (source 1, target 6)
    for row in rows:
        assert not (row['source'] == '1' and row['target'] == '6'), "Cross-region edge should be excluded."

    assert reader.fieldnames == COLUMNS, f"CSV headers must be exactly {COLUMNS}."
    try:
        actual = Counter(
            (int(row["source"]), int(row["target"]), int(row["weight"]),
             int(row["timestamp"]), row["region"])
            for row in rows
        )
    except (KeyError, TypeError, ValueError) as error:
        pytest.fail(f"CSV contains invalid values: {error}")

    with sqlite3.connect(DB_PATH) as conn:
        expected = expected_rows(conn)
        query_rows = execute_query(conn, read_query())
    assert actual == expected, "recent_edges.csv does not match the correct database results."
    assert actual == query_rows, "recent_edges.csv does not match fixed_query.sql output."


def test_report_json():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON.")

    assert "shortest_path" in report, "report.json missing 'shortest_path' key."
    assert "max_degree_node" in report, "report.json missing 'max_degree_node' key."

    assert report["max_degree_node"] == 3, f"Expected max_degree_node to be 3, got {report['max_degree_node']}."

    path = report["shortest_path"]
    assert isinstance(path, list), "shortest_path must be a list."
    assert len(path) == 3, f"Expected shortest_path length 3, got {len(path)}."
    assert path[0] == 1, f"Expected shortest_path to start with 1, got {path[0]}."
    assert path[-1] == 5, f"Expected shortest_path to end with 5, got {path[-1]}."
    assert path[1] in [2, 3], f"Expected intermediate node to be 2 or 3, got {path[1]}."


def test_graph_analytics_script():
    script_path = "/home/user/graph_analytics.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    with open(CSV_PATH, "r", newline="") as f:
        original_rows = list(csv.DictReader(f))

    csv_backup = tempfile.mktemp(prefix="recent_edges_", suffix=".csv")
    report_backup = tempfile.mktemp(prefix="report_", suffix=".json")
    shutil.copy2(CSV_PATH, csv_backup)
    had_report = os.path.exists(REPORT_PATH)
    if had_report:
        shutil.copy2(REPORT_PATH, report_backup)

    try:
        # Require the script to regenerate, rather than merely leave, the report.
        report = run_graph_script()
        assert_graph_report(report, original_rows)

        # Randomized probe graph. Edges are intentionally represented only once;
        # correct traversal and degree calculations must therefore be undirected.
        extra = secrets.SystemRandom().sample(range(20, 100000), 4)
        a, b, c, d = extra
        probe_edges = [
            (1, a), (a, b), (b, 5),
            (c, 1), (c, a), (c, b), (c, 5),
            (d, 1), (d, a), (d, b), (d, 5),
        ]
        probe_rows = []
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=COLUMNS)
            writer.writeheader()
            for number, (source, target) in enumerate(probe_edges):
                row = {
                    "source": source,
                    "target": target,
                    "weight": secrets.randbelow(10000) + 1,
                    "timestamp": secrets.randbelow(1000000) + number,
                    "region": "probe_" + secrets.token_hex(3),
                }
                probe_rows.append({key: str(value) for key, value in row.items()})
                writer.writerow(row)

        probe_report = run_graph_script()
        assert_graph_report(probe_report, probe_rows)
    finally:
        shutil.copy2(csv_backup, CSV_PATH)
        os.remove(csv_backup)
        if had_report:
            shutil.copy2(report_backup, REPORT_PATH)
            os.remove(report_backup)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
