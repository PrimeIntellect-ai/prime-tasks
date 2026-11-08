#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import heapq
import os
import re
import shutil
import sqlite3
import subprocess
import uuid

import pytest

DB_PATH = "/home/user/logistics.db"
CSV_PATH = "/home/user/optimal_route.csv"
SCRIPT_PATH = "/home/user/analyze.py"
NETWORK_PATH = "/home/user/network.csv"


def run_script(start, end):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--start", start, "--end", end],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    )


def derive_shortest_path(rows, start, end):
    graph = {}
    for row in rows:
        cost = float(row["base_cost"]) * (1.0 + float(row["delay_factor"]))
        graph.setdefault(row["source_city"], []).append((row["target_city"], cost))

    distances = {start: 0.0}
    previous = {}
    queue = [(0.0, start)]
    while queue:
        distance, city = heapq.heappop(queue)
        if distance != distances.get(city):
            continue
        if city == end:
            break
        for target, hop_cost in graph.get(city, []):
            candidate = distance + hop_cost
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = (city, hop_cost)
                heapq.heappush(queue, (candidate, target))

    assert end in distances, "Verifier-generated graph unexpectedly has no route."
    reversed_path = [(end, previous[end][1])]
    city = end
    while city != start:
        city = previous[city][0]
        if city == start:
            reversed_path.append((city, 0.0))
        else:
            reversed_path.append((city, previous[city][1]))
    return list(reversed(reversed_path))


def assert_database_matches(rows, expected_path):
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT source_city, target_city, base_cost, delay_factor FROM routes")
        actual_routes = cursor.fetchall()
        assert len(actual_routes) == len(rows), "The routes table does not contain exactly the input data."
        expected_by_edge = {
            (r["source_city"], r["target_city"]): (float(r["base_cost"]), float(r["delay_factor"]))
            for r in rows
        }
        for source, target, base, delay in actual_routes:
            assert (source, target) in expected_by_edge, f"Unexpected route {(source, target)} in routes table."
            expected_base, expected_delay = expected_by_edge[(source, target)]
            assert float(base) == pytest.approx(expected_base)
            assert float(delay) == pytest.approx(expected_delay)

        cursor.execute("SELECT step_order, city_name, hop_cost FROM path_sequence ORDER BY step_order")
        actual_path = cursor.fetchall()
        assert len(actual_path) == len(expected_path), "path_sequence has the wrong number of rows."
        for step, (actual, expected) in enumerate(zip(actual_path, expected_path), 1):
            assert actual[0] == step
            assert actual[1] == expected[0]
            assert float(actual[2]) == pytest.approx(expected[1])
    finally:
        conn.close()


def assert_csv_matches(expected_path):
    assert os.path.isfile(CSV_PATH), f"Output CSV file {CSV_PATH} is missing."
    with open(CSV_PATH, newline="") as handle:
        data = list(csv.reader(handle))
    assert data and data[0] == ["step_order", "city_name", "hop_cost", "cumulative_cost"]
    assert len(data[1:]) == len(expected_path)

    cumulative = 0.0
    for step, (row, expected) in enumerate(zip(data[1:], expected_path), 1):
        cumulative += expected[1]
        assert len(row) == 4
        assert row[0] == str(step)
        assert row[1] == expected[0]
        assert re.fullmatch(r"-?\d+(?:\.\d{1,2})?", row[2]), "hop_cost is not rounded to at most 2 decimal places."
        assert re.fullmatch(r"-?\d+(?:\.\d{1,2})?", row[3]), "cumulative_cost is not rounded to at most 2 decimal places."
        assert float(row[2]) == pytest.approx(round(expected[1], 2))
        assert float(row[3]) == pytest.approx(round(cumulative, 2))


def test_script_exists_and_uses_required_sql_features():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    assigned_strings = {}
    all_strings = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            all_strings.append(node.value)
        if isinstance(node, ast.Assign):
            try:
                value = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                continue
            if isinstance(value, str):
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        assigned_strings[target.id] = value

    insert_statements = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        if not isinstance(node.func, ast.Attribute) or node.func.attr not in {"execute", "executemany"}:
            continue
        sql = None
        first = node.args[0]
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            sql = first.value
        elif isinstance(first, ast.Name):
            sql = assigned_strings.get(first.id)
        if sql and re.search(r"\bINSERT\s+INTO\b", sql, re.IGNORECASE):
            insert_statements.append(sql)

    assert any(re.search(r"\bINSERT\s+INTO\s+routes\b", sql, re.IGNORECASE) for sql in insert_statements), \
        "No SQL insertion into routes was found."
    assert any(re.search(r"\bINSERT\s+INTO\s+path_sequence\b", sql, re.IGNORECASE) for sql in insert_statements), \
        "No SQL insertion into path_sequence was found."
    for sql in insert_statements:
        assert re.search(r"\?|[:@$][A-Za-z_]\w*", sql), "An INSERT statement is not parameterized."

    sql_text = "\n".join(all_strings)
    assert re.search(r"\bSUM\s*\([^)]*\)\s*OVER\s*\(", sql_text, re.IGNORECASE | re.DOTALL), \
        "No SQL SUM window function was found."
    assert re.search(r"\bORDER\s+BY\s+step_order\b", sql_text, re.IGNORECASE), \
        "The window query is not ordered by step_order."


def test_script_executes_on_derived_non_hardcoded_input():
    with open(NETWORK_PATH, "rb") as handle:
        original_network = handle.read()

    prefix = "Verifier_" + uuid.uuid4().hex
    start, a, b, end, dead = [prefix + suffix for suffix in ("_Start", "_A", "_B", "_End", "_Dead")]
    rows = [
        {"source_city": start, "target_city": a, "base_cost": "5.55", "delay_factor": "0.10"},
        {"source_city": start, "target_city": b, "base_cost": "2", "delay_factor": "0.50"},
        {"source_city": b, "target_city": a, "base_cost": "1.23", "delay_factor": "0.10"},
        {"source_city": a, "target_city": end, "base_cost": "4", "delay_factor": "0.25"},
        {"source_city": b, "target_city": end, "base_cost": "10", "delay_factor": "0"},
        {"source_city": start, "target_city": end, "base_cost": "20", "delay_factor": "0"},
        {"source_city": dead, "target_city": start, "base_cost": "0.1", "delay_factor": "0"},
    ]
    expected_path = derive_shortest_path(rows, start, end)

    try:
        with open(NETWORK_PATH, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["source_city", "target_city", "base_cost", "delay_factor"])
            writer.writeheader()
            writer.writerows(rows)
        for artifact in (DB_PATH, CSV_PATH):
            if os.path.exists(artifact):
                os.remove(artifact)
        run_script(start, end)
        assert_database_matches(rows, expected_path)
        assert_csv_matches(expected_path)
    finally:
        with open(NETWORK_PATH, "wb") as handle:
            handle.write(original_network)
        for artifact in (DB_PATH, CSV_PATH):
            if os.path.exists(artifact):
                os.remove(artifact)
        run_script("Alpha", "Zeta")


def test_database_and_tables_exist():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='routes'")
    assert cursor.fetchone() is not None, "Table 'routes' does not exist in the database."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='path_sequence'")
    assert cursor.fetchone() is not None, "Table 'path_sequence' does not exist in the database."

    conn.close()


def test_routes_index_exists():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='routes'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No index found on 'routes' table."

    index_found = False
    for idx in indexes:
        index_name = idx[0]
        if index_name.startswith("sqlite_"):
            continue

        cursor.execute(f"PRAGMA index_info('{index_name}')")
        columns = [row[2] for row in cursor.fetchall()]
        if "source_city" in columns and "target_city" in columns:
            index_found = True
            break

    assert index_found, "Composite index on 'source_city' and 'target_city' is missing."
    conn.close()


def test_final_database_contents():
    with open(NETWORK_PATH, newline="") as handle:
        rows = list(csv.DictReader(handle))
    expected_path = derive_shortest_path(rows, "Alpha", "Zeta")
    assert_database_matches(rows, expected_path)


def test_optimal_route_csv():
    assert os.path.exists(CSV_PATH), f"Output CSV file {CSV_PATH} is missing."

    expected_data = [
        ["1", "Alpha", "0.0", "0.0"],
        ["2", "Gamma", "10.0", "10.0"],
        ["3", "Delta", "5.0", "15.0"],
        ["4", "Epsilon", "11.0", "26.0"],
        ["5", "Zeta", "8.0", "34.0"]
    ]

    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["step_order", "city_name", "hop_cost", "cumulative_cost"], "CSV header is incorrect."

        rows = list(reader)
        assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(rows)}."

        for i, (row, expected_row) in enumerate(zip(rows, expected_data)):
            assert row[0] == expected_row[0], f"Row {i+1} step_order mismatch: {row[0]} != {expected_row[0]}"
            assert row[1] == expected_row[1], f"Row {i+1} city_name mismatch: {row[1]} != {expected_row[1]}"
            assert float(row[2]) == float(expected_row[2]), f"Row {i+1} hop_cost mismatch: {row[2]} != {expected_row[2]}"
            assert float(row[3]) == float(expected_row[3]), f"Row {i+1} cumulative_cost mismatch: {row[3]} != {expected_row[3]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
