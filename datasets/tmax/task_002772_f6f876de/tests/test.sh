#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/analyze_graph.py"
DB_PATH = "/home/user/research_data.db"
JSON_PATH = "/home/user/path_results.json"


def _constant_strings(tree):
    values = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value_node, ast.Constant) and isinstance(value_node.value, str):
                for target in targets:
                    if isinstance(target, ast.Name):
                        values[target.id] = value_node.value
    return values


def _sql_text(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    if isinstance(node, ast.JoinedStr):
        return "".join(
            part.value for part in node.values
            if isinstance(part, ast.Constant) and isinstance(part.value, str)
        )
    return None


def _assert_parameterized_metadata_queries(source):
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    constants = _constant_strings(tree)
    parameterized_selects = []
    bind_marker = re.compile(r"\?|(?<!:):[A-Za-z_][A-Za-z0-9_]*|\$[A-Za-z_][A-Za-z0-9_]*|@[A-Za-z_][A-Za-z0-9_]*")

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in {"execute", "executemany"} or len(node.args) < 2:
            continue
        sql = _sql_text(node.args[0], constants)
        if sql and re.search(r"\bSELECT\b", sql, re.IGNORECASE) and bind_marker.search(sql):
            parameterized_selects.append(sql.lower())

    assert parameterized_selects, (
        "The script must retrieve path-paper metadata with parameterized SELECT queries."
    )
    combined = "\n".join(parameterized_selects)
    assert "tbl_nodes" in combined, (
        "A parameterized SELECT must retrieve paper title/year data from tbl_nodes."
    )
    assert "tbl_creators" in combined, (
        "A parameterized SELECT must retrieve author data from tbl_creators."
    )


def _randomize_fixture():
    """Choose a fresh valid shortest path and unpredictable metadata before execution."""
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT node_id, p_title FROM tbl_nodes")
        ids = {title: node_id for node_id, title in cursor.fetchall()}

        start = ids["Quantum Origins"]
        end = ids["Macroscopic Superposition"]
        route_a = [start, ids["Subatomic Forces"], ids["Decoherence Models"], end]
        route_b = [start, ids["Entanglement Dynamics"], ids["Deadlock avoidance in distributed databases"], end]
        route = secrets.choice([route_a, route_b])

        cursor.execute("DELETE FROM tbl_edges")
        cursor.executemany(
            "INSERT INTO tbl_edges(from_node, to_node) VALUES (?, ?)",
            list(zip(route, route[1:])),
        )

        # Keep an unreachable cycle so traversal still has to respect edge direction.
        unused = route_b[1:3] if route == route_a else route_a[1:3]
        cursor.executemany(
            "INSERT INTO tbl_edges(from_node, to_node) VALUES (?, ?)",
            [(unused[0], unused[1]), (unused[1], unused[0])],
        )

        year_delta = secrets.randbelow(500) + 1
        cursor.execute("UPDATE tbl_nodes SET p_year = p_year + ?", (year_delta,))
        token = secrets.token_hex(8)
        cursor.executemany(
            "INSERT INTO tbl_creators(node_id, creator_name) VALUES (?, ?)",
            [(node_id, f"Verifier Author {token}-{position}") for position, node_id in enumerate(route)],
        )
        conn.commit()
    finally:
        conn.close()


def test_pipeline_and_final_results_json():
    assert os.path.isfile(SCRIPT_PATH), f"Required Python script {SCRIPT_PATH} is missing."
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    _assert_parameterized_metadata_queries(source)

    _randomize_fixture()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} is missing after running the script."

    with open(JSON_PATH, "r", encoding="utf-8") as handle:
        try:
            actual_data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not valid JSON.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Load nodes
    cursor.execute("SELECT node_id, p_title, p_year FROM tbl_nodes")
    nodes = {row[0]: {"title": row[1], "year": row[2]} for row in cursor.fetchall()}

    # Load edges
    cursor.execute("SELECT from_node, to_node FROM tbl_edges")
    edges = cursor.fetchall()

    # Load authors
    cursor.execute("SELECT node_id, creator_name FROM tbl_creators")
    authors = {}
    for row in cursor.fetchall():
        authors.setdefault(row[0], []).append(row[1])
    conn.close()

    for node_id in authors:
        authors[node_id].sort()

    # Identify start and end nodes
    start_id = None
    end_id = None
    for nid, ndata in nodes.items():
        if ndata["title"] == "Quantum Origins":
            start_id = nid
        elif ndata["title"] == "Macroscopic Superposition":
            end_id = nid

    assert start_id is not None, "Start node 'Quantum Origins' missing in DB."
    assert end_id is not None, "End node 'Macroscopic Superposition' missing in DB."

    # Build adjacency list and find shortest path using BFS
    adj = {}
    for u, v in edges:
        adj.setdefault(u, []).append(v)

    queue = deque([[start_id]])
    visited = {start_id}
    shortest_path = None

    while queue:
        path = queue.popleft()
        curr = path[-1]
        if curr == end_id:
            shortest_path = path
            break
        for nxt in adj.get(curr, []):
            if nxt not in visited:
                visited.add(nxt)
                queue.append(path + [nxt])

    assert shortest_path is not None, "No path found between start and end nodes in DB."

    # Construct expected JSON structure
    expected_data = []
    for nid in shortest_path:
        expected_data.append({
            "title": nodes[nid]["title"],
            "year": nodes[nid]["year"],
            "authors": authors.get(nid, []),
        })

    assert actual_data == expected_data, (
        f"JSON content does not match the expected shortest path.\n"
        f"Expected: {json.dumps(expected_data, indent=2)}\n"
        f"Actual: {json.dumps(actual_data, indent=2)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
