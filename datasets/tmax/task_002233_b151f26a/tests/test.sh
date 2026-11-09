#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import heapq
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter

import pytest

DB_PATH = "/home/user/network_topology.db"
CSV_PATH = "/home/user/shortest_paths.csv"
COMPUTE_SCRIPT = "/home/user/compute_paths.py"
SANITIZER_SCRIPT = "/home/user/query_sanitizer.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"

EXPECTED_NODES = [
    (305, "nodeA"),
    (992, "nodeB"),
    (1042, "root"),
    (2000, "nodeC"),
]
EXPECTED_EDGES = [
    (1042, 305, 10, "FIBER"),
    (305, 992, 5, "FIBER"),
    (992, 2000, 15, "FIBER"),
    (1042, 992, 20, "FIBER"),
]


def run_python(script, *args, timeout=15):
    return subprocess.run(
        ["python3", script, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_corrupted_index_dropped():
    """Verify that the corrupted index 'idx_edges_corrupt' has been dropped."""
    assert os.path.isfile(DB_PATH), f"Database not found at {DB_PATH}"
    with sqlite3.connect(DB_PATH) as conn:
        result = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_corrupt'"
        ).fetchall()
    assert len(result) == 0, "The corrupted index 'idx_edges_corrupt' still exists in the database."


def assert_original_database_intact():
    assert os.path.isfile(DB_PATH), f"Database not found at {DB_PATH}"
    with sqlite3.connect(DB_PATH) as conn:
        node_columns = [r[1:3] for r in conn.execute("PRAGMA table_info(nodes)")]
        edge_columns = [r[1:3] for r in conn.execute("PRAGMA table_info(edges)")]
        nodes = conn.execute("SELECT id, hostname FROM nodes ORDER BY id").fetchall()
        edges = conn.execute("SELECT source, target, cost, edge_type FROM edges").fetchall()
    assert node_columns == [("id", "INTEGER"), ("hostname", "TEXT")]
    assert edge_columns == [
        ("source", "INTEGER"),
        ("target", "INTEGER"),
        ("cost", "INTEGER"),
        ("edge_type", "TEXT"),
    ]
    assert nodes == EXPECTED_NODES, "The required topology nodes were deleted or modified."
    assert Counter(edges) == Counter(EXPECTED_EDGES), "The required topology edges were deleted, modified, or supplemented."


def test_database_topology_preserved():
    assert_original_database_intact()


def compute_expected_paths(db_path, root_node, edge_type):
    """Compute the expected shortest paths independently using Dijkstra's algorithm."""
    with sqlite3.connect(db_path) as conn:
        rows = conn.execute(
            """
            SELECT source, target, MIN(cost)
            FROM edges
            WHERE edge_type = ?
            GROUP BY source, target
            """,
            (edge_type,),
        ).fetchall()

    graph = {}
    for source, target, cost in rows:
        graph.setdefault(source, []).append((target, cost))

    pq = [(0, root_node, [root_node])]
    distances = {root_node: 0}
    paths = {root_node: [root_node]}
    while pq:
        distance, current, path = heapq.heappop(pq)
        if distance != distances.get(current):
            continue
        for neighbor, weight in graph.get(current, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                paths[neighbor] = path + [neighbor]
                heapq.heappush(pq, (candidate, neighbor, paths[neighbor]))

    distances.pop(root_node, None)
    paths.pop(root_node, None)
    return distances, paths


def assert_csv_matches(expected_distances, expected_paths):
    assert os.path.isfile(CSV_PATH), f"Shortest paths CSV not found at {CSV_PATH}"
    actual_distances = {}
    actual_paths = {}
    row_count = 0

    with open(CSV_PATH, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["target_node_id", "total_cost", "path_string"], (
            "CSV headers are incorrect. Expected "
            "['target_node_id', 'total_cost', 'path_string'], "
            f"got {reader.fieldnames}"
        )
        for row in reader:
            row_count += 1
            target = int(row["target_node_id"])
            assert target not in actual_distances, f"Duplicate CSV row for target node {target}."
            actual_distances[target] = int(row["total_cost"])
            actual_paths[target] = row["path_string"]

    assert len(actual_distances) > 0, "The generated CSV contains no path data."
    missing_nodes = set(expected_distances) - set(actual_distances)
    assert not missing_nodes, f"CSV is missing shortest paths for nodes: {missing_nodes}"
    assert set(actual_distances) == set(expected_distances), (
        f"CSV contains unexpected target nodes: {set(actual_distances) - set(expected_distances)}"
    )
    assert row_count == len(expected_distances)

    for node, expected_cost in expected_distances.items():
        assert actual_distances[node] == expected_cost, (
            f"Incorrect cost for target node {node}. Expected {expected_cost}, "
            f"got {actual_distances[node]}."
        )
        expected_path = "->".join(map(str, expected_paths[node]))
        assert actual_paths[node] == expected_path, (
            f"Incorrect path string for target node {node}. Expected {expected_path}, "
            f"got {actual_paths[node]}."
        )


def assert_compute_script_artifact():
    assert os.path.isfile(COMPUTE_SCRIPT), f"Compute script not found at {COMPUTE_SCRIPT}"
    assert os.access(COMPUTE_SCRIPT, os.X_OK), "compute_paths.py is not executable."
    with open(COMPUTE_SCRIPT, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=COMPUTE_SCRIPT)
    sql_literals = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    has_recursive_sql = any(
        re.search(r"\bWITH\s+RECURSIVE\b", value, re.IGNORECASE)
        and re.search(r"\bSELECT\b", value, re.IGNORECASE)
        for value in sql_literals
    )
    has_execute_call = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"execute", "executemany"}
        for node in ast.walk(tree)
    )
    assert has_recursive_sql, "compute_paths.py does not contain a recursive SQL CTE."
    assert has_execute_call, "compute_paths.py does not execute a SQL statement."


def run_compute_and_check(expected_distances, expected_paths):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = run_python(COMPUTE_SCRIPT, timeout=20)
    assert result.returncode == 0, (
        f"compute_paths.py failed with status {result.returncode}: "
        f"{result.stderr[-1000:]}"
    )
    assert_csv_matches(expected_distances, expected_paths)


def test_shortest_paths_csv_correctness():
    """Execute the requested artifact and verify the canonical topology output."""
    assert_compute_script_artifact()
    assert_original_database_intact()
    expected_distances, expected_paths = compute_expected_paths(DB_PATH, 1042, "FIBER")
    run_compute_and_check(expected_distances, expected_paths)
    assert_original_database_intact()


def test_compute_paths_on_unseen_topology():
    """Ensure output is computed from the database rather than hardcoded."""
    assert_compute_script_artifact()
    with tempfile.TemporaryDirectory() as tmpdir:
        backup = os.path.join(tmpdir, "network_topology.db")
        shutil.copy2(DB_PATH, backup)
        try:
            rng = random.Random(secrets.randbits(128))
            candidates = [n for n in range(3000, 900000) if n != 1042]
            a, b, c, d, e = rng.sample(candidates, 5)
            x, y, z, w, q = [rng.randint(2, 30) for _ in range(5)]
            challenge_nodes = [
                (1042, "root"), (a, "alpha"), (b, "beta"),
                (c, "gamma"), (d, "delta"), (e, "epsilon"),
            ]
            challenge_edges = [
                (1042, a, x, "FIBER"),
                (a, b, y, "FIBER"),
                (1042, b, x + y + 17, "FIBER"),
                (b, c, z, "FIBER"),
                (a, c, y + z + 11, "FIBER"),
                (c, d, w, "FIBER"),
                (1042, d, x + y + z + w + 40, "FIBER"),
                (b, e, q, "FIBER"),
                (1042, c, 1, "COPPER"),
                (1042, e, 1, "WIRELESS"),
            ]
            with sqlite3.connect(DB_PATH) as conn:
                conn.execute("DELETE FROM edges")
                conn.execute("DELETE FROM nodes")
                conn.executemany("INSERT INTO nodes(id, hostname) VALUES (?, ?)", challenge_nodes)
                conn.executemany(
                    "INSERT INTO edges(source, target, cost, edge_type) VALUES (?, ?, ?, ?)",
                    challenge_edges,
                )
                conn.commit()

            expected_distances, expected_paths = compute_expected_paths(DB_PATH, 1042, "FIBER")
            run_compute_and_check(expected_distances, expected_paths)
            with sqlite3.connect(DB_PATH) as conn:
                nodes_after = conn.execute("SELECT id, hostname FROM nodes").fetchall()
                edges_after = conn.execute(
                    "SELECT source, target, cost, edge_type FROM edges"
                ).fetchall()
            assert Counter(nodes_after) == Counter(challenge_nodes), "Compute script modified the nodes table."
            assert Counter(edges_after) == Counter(challenge_edges), "Compute script modified the edges table."
        finally:
            for suffix in ("", "-wal", "-shm"):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)
            shutil.copy2(backup, DB_PATH)
            # Leave the requested canonical CSV as the final artifact.
            expected_distances, expected_paths = compute_expected_paths(DB_PATH, 1042, "FIBER")
            run_compute_and_check(expected_distances, expected_paths)


def test_query_sanitizer_adversarial_corpus():
    """Preserve the original corpus checks."""
    assert os.path.isfile(SANITIZER_SCRIPT), f"Query sanitizer script not found at {SANITIZER_SCRIPT}"
    assert os.access(SANITIZER_SCRIPT, os.X_OK), "query_sanitizer.py is not executable."

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, "No clean corpus files found to test."
    assert len(evil_files) > 0, "No evil corpus files found to test."

    clean_failed = []
    evil_bypassed = []
    for clean_file in clean_files:
        if run_python(SANITIZER_SCRIPT, clean_file).returncode != 0:
            clean_failed.append(os.path.basename(clean_file))
    for evil_file in evil_files:
        if run_python(SANITIZER_SCRIPT, evil_file).returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def randomized_case(word):
    return "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in word)


def test_query_sanitizer_unseen_queries_and_cli_contract():
    """Exercise randomized filenames and unseen safe and malicious query contents."""
    assert os.path.isfile(SANITIZER_SCRIPT), f"Query sanitizer script not found at {SANITIZER_SCRIPT}"
    assert os.access(SANITIZER_SCRIPT, os.X_OK), "query_sanitizer.py is not executable."

    token = secrets.token_hex(8)
    clean_queries = [
        "SELECT 1;",
        "\n\t" + randomized_case("select") + " hostname FROM nodes WHERE id = 1042;\n",
        "SELECT id, hostname FROM nodes WHERE hostname = '" + token + "';",
        "WITH chosen AS (SELECT id FROM nodes WHERE id > 0) SELECT id FROM chosen;",
        "WITH RECURSIVE nums(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM nums WHERE x < 3) SELECT x FROM nums;",
        "SELECT COUNT(*) FROM edges WHERE edge_type = 'FIBER';",
    ]
    evil_queries = [
        "SELECT * FROM nodes; " + randomized_case("drop") + " TABLE edges;",
        randomized_case("delete") + " FROM nodes WHERE id = 1042;",
        randomized_case("update") + " nodes SET hostname = '" + token + "';",
        randomized_case("insert") + " INTO nodes(id, hostname) VALUES (999999, 'x');",
        randomized_case("alter") + " TABLE nodes ADD COLUMN compromised TEXT;",
        "SELECT * FROM nodes -- " + token + "\nWHERE id = 1;",
        "SELECT * FROM nodes /* " + token + " */ WHERE id = 1;",
        randomized_case("create") + " TABLE stolen(x INTEGER);",
        randomized_case("attach") + " DATABASE '/tmp/other.db' AS other;",
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        for expected, queries in ((0, clean_queries), (1, evil_queries)):
            for query in queries:
                filename = os.path.join(tmpdir, secrets.token_hex(12) + ".sql")
                with open(filename, "w", encoding="utf-8") as handle:
                    handle.write(query)
                result = run_python(SANITIZER_SCRIPT, filename)
                assert result.returncode == expected, (
                    f"Sanitizer returned {result.returncode}, expected {expected}, for query: {query!r}"
                )

    assert run_python(SANITIZER_SCRIPT).returncode != 0, "Sanitizer accepted a missing query-file argument."
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as first, \
         tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False) as second:
        first.write("SELECT 1;")
        second.write("SELECT 2;")
        first_path, second_path = first.name, second.name
    try:
        assert run_python(SANITIZER_SCRIPT, first_path, second_path).returncode != 0, (
            "Sanitizer accepted more than one argument."
        )
    finally:
        os.remove(first_path)
        os.remove(second_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
