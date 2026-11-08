#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import heapq
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

PY_PATH = "/home/user/pathfinder.py"
DB_PATH = "/home/user/concepts.db"


def run_pathfinder(start, end, timeout=10):
    return subprocess.run(
        ["python3", PY_PATH, str(start), str(end)],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_optimize_sql_exists_and_correct():
    sql_path = "/home/user/optimize.sql"
    assert os.path.isfile(sql_path), f"File {sql_path} does not exist."

    with open(sql_path, "r", encoding="utf-8") as f:
        original_content = f.read()
    content = original_content.lower()

    # Preserve the original assertions.
    assert "create index" in content, "optimize.sql does not contain a CREATE INDEX statement."
    assert "dependencies" in content, "optimize.sql does not reference the 'dependencies' table."
    assert "source" in content, "optimize.sql does not index the 'source' column."

    # Execute the submitted SQL on a disposable database copy and verify that it
    # creates a usable index whose leading column is dependencies.source.
    with tempfile.TemporaryDirectory() as td:
        db_copy = os.path.join(td, "concepts.db")
        shutil.copy2(DB_PATH, db_copy)
        conn = sqlite3.connect(db_copy)
        try:
            existing = conn.execute(
                "SELECT name FROM sqlite_master WHERE type = ? AND tbl_name = ? AND sql IS NOT NULL",
                ("index", "dependencies"),
            ).fetchall()
            for (name,) in existing:
                escaped = name.replace('"', '""')
                conn.execute(f'DROP INDEX "{escaped}"')
            conn.commit()

            conn.executescript(original_content)

            indexes = conn.execute("PRAGMA index_list('dependencies')").fetchall()
            suitable = []
            for row in indexes:
                index_name = row[1]
                escaped = index_name.replace("'", "''")
                columns = conn.execute(
                    f"PRAGMA index_info('{escaped}')"
                ).fetchall()
                if columns and columns[0][2].lower() == "source":
                    suitable.append(index_name)

            assert suitable, "optimize.sql did not create an index led by dependencies.source."

            plan = conn.execute(
                "EXPLAIN QUERY PLAN SELECT target, weight FROM dependencies WHERE source = ?",
                (15,),
            ).fetchall()
            plan_text = " ".join(str(field) for row in plan for field in row).lower()
            assert any(name.lower() in plan_text for name in suitable), (
                "SQLite does not use the created source index for outgoing relationship lookups."
            )
        finally:
            conn.close()


def test_pathfinder_py_exists_and_parameterized():
    assert os.path.isfile(PY_PATH), f"File {PY_PATH} does not exist."

    with open(PY_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "?" in content or ":" in content or "%s" in content, "pathfinder.py does not appear to use parameterized queries."

    tree = ast.parse(content, filename=PY_PATH)
    database_calls = []
    parameterized_calls = []
    unsafe_direct_queries = []
    has_connect = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = None
        if isinstance(node.func, ast.Attribute):
            call_name = node.func.attr
        elif isinstance(node.func, ast.Name):
            call_name = node.func.id

        if call_name == "connect":
            has_connect = True
        if call_name not in ("execute", "executemany"):
            continue

        database_calls.append(node)
        if len(node.args) >= 2 or any(k.arg in ("parameters", "params") for k in node.keywords):
            parameterized_calls.append(node)

        if node.args:
            query = node.args[0]
            if isinstance(query, ast.JoinedStr):
                unsafe_direct_queries.append(node)
            elif isinstance(query, ast.BinOp) and isinstance(query.op, (ast.Add, ast.Mod)):
                unsafe_direct_queries.append(node)
            elif isinstance(query, ast.Call) and isinstance(query.func, ast.Attribute) and query.func.attr == "format":
                unsafe_direct_queries.append(node)

    assert has_connect, "pathfinder.py does not appear to connect to the SQLite database."
    assert database_calls, "pathfinder.py does not appear to execute any database queries."
    assert parameterized_calls, "pathfinder.py does not execute a query with bound parameters."
    assert not unsafe_direct_queries, "pathfinder.py directly interpolates values into a SQL query."


def test_pathfinder_execution():
    assert os.path.isfile(PY_PATH), f"File {PY_PATH} does not exist."

    # Preserve the original fixed execution assertion.
    result = run_pathfinder(15, 85)
    assert result.returncode == 0, f"pathfinder.py failed to execute: {result.stderr}"
    output = result.stdout.strip()
    assert output == "15,33,71,85", f"pathfinder.py output incorrect. Expected '15,33,71,85', got '{output}'"


def test_pathfinder_requires_exactly_two_arguments():
    for args in (["python3", PY_PATH, "15"], ["python3", PY_PATH, "15", "85", "99"]):
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, "pathfinder.py must reject invocation without exactly two IDs."


def shortest_path(nodes, edges, start, end):
    adjacency = {node: [] for node in nodes}
    for (source, target), weight in edges.items():
        adjacency[source].append((target, weight))

    distances = {start: 0.0}
    previous = {}
    queue = [(0.0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == end:
            break
        for target, weight in adjacency[node]:
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert end in distances
    path = [end]
    while path[-1] != start:
        path.append(previous[path[-1]])
    path.reverse()
    return path


def test_pathfinder_dynamic_graph_traversal():
    # Replace the database temporarily with a fresh randomized graph having the
    # same reverse-engineered schema. Expected paths are independently derived.
    backup_fd, backup_path = tempfile.mkstemp(prefix="concepts-backup-", suffix=".db")
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    rng = random.SystemRandom()
    nodes = rng.sample(range(1000, 1000000), 20)
    edges = {}

    # A directed ring guarantees reachability. Random positive non-integral
    # weights and additional edges make fixed-output solutions ineffective.
    for i, source in enumerate(nodes):
        edges[(source, nodes[(i + 1) % len(nodes)])] = rng.uniform(2.0, 20.0)
    while len(edges) < 85:
        source, target = rng.sample(nodes, 2)
        edges[(source, target)] = rng.uniform(1.0, 25.0)

    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("CREATE TABLE concepts (id INTEGER PRIMARY KEY, name TEXT)")
            conn.execute("CREATE TABLE dependencies (source INTEGER, target INTEGER, weight REAL)")
            conn.executemany(
                "INSERT INTO concepts (id, name) VALUES (?, ?)",
                [(node, f"Test Concept {node}") for node in nodes],
            )
            conn.executemany(
                "INSERT INTO dependencies (source, target, weight) VALUES (?, ?, ?)",
                [(source, target, weight) for (source, target), weight in edges.items()],
            )
            conn.commit()
        finally:
            conn.close()

        pairs = [tuple(rng.sample(nodes, 2)) for _ in range(7)]
        for start, end in pairs:
            expected = shortest_path(nodes, edges, start, end)
            result = run_pathfinder(start, end)
            assert result.returncode == 0, f"pathfinder.py failed on dynamic input: {result.stderr}"
            assert result.stdout.strip() == ",".join(map(str, expected)), (
                f"Incorrect shortest path for dynamically generated pair {start}->{end}."
            )

        # Change the graph and require the answer for a previously tested pair
        # to change, proving that results are obtained from current DB contents.
        start, end = pairs[0]
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute(
                "INSERT INTO dependencies (source, target, weight) VALUES (?, ?, ?)",
                (start, end, 0.0001),
            )
            conn.commit()
        finally:
            conn.close()

        result = run_pathfinder(start, end)
        assert result.returncode == 0, f"pathfinder.py failed after graph update: {result.stderr}"
        assert result.stdout.strip() == f"{start},{end}", "pathfinder.py did not respond to changed database contents."
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.move(backup_path, DB_PATH)


def test_path_txt_exists_and_correct():
    txt_path = "/home/user/path.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."

    with open(txt_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "15,33,71,85", f"path.txt content is incorrect. Expected '15,33,71,85', got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
