#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/etl_data.db"
RESULT_PATH = "/home/user/aggregation_result.txt"
SOURCE_PATH = "/home/user/graph_etl.cpp"
BINARY_PATH = "/home/user/graph_etl"
REBUILT_PATH = "/tmp/verifier_graph_etl"

EXPECTED_NODES = [(1, 10), (2, 20), (3, 30), (4, 40), (5, 50)]
EXPECTED_EDGES = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 4)]
EXPECTED_ROWS = [
    (1, 3, 60, 1),
    (1, 4, 100, 1),
    (2, 5, 45, 0),
    (3, 4, 70, 1),
]


def reset_database():
    if os.path.lexists(DB_PATH):
        os.unlink(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.executescript("""
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, weight INTEGER);
        CREATE TABLE edges (source INTEGER, target INTEGER);
        CREATE TABLE materialized_paths (
            source INTEGER,
            target INTEGER,
            total_weight INTEGER,
            is_valid INTEGER
        );

        INSERT INTO nodes (id, weight) VALUES
            (1, 10), (2, 20), (3, 30), (4, 40), (5, 50);
        INSERT INTO edges (source, target) VALUES
            (1, 2), (2, 3), (3, 4), (1, 5), (5, 4);
        INSERT INTO materialized_paths
            (source, target, total_weight, is_valid) VALUES
            (1, 4, 150, 1),
            (1, 3, 60, 1),
            (2, 5, 45, 1),
            (3, 4, 10, 1);
    """)
    conn.commit()
    conn.close()
    if os.path.lexists(RESULT_PATH):
        os.unlink(RESULT_PATH)


def assert_expected_fixed_state():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, weight FROM nodes")
    assert sorted(cursor.fetchall()) == EXPECTED_NODES, "The nodes table was modified."
    cursor.execute("SELECT source, target FROM edges")
    assert sorted(cursor.fetchall()) == EXPECTED_EDGES, "The edges table was modified."
    cursor.execute(
        "SELECT source, target, total_weight, is_valid FROM materialized_paths"
    )
    assert sorted(cursor.fetchall()) == EXPECTED_ROWS, (
        "materialized_paths does not contain the required corrected rows."
    )
    conn.close()

    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r") as f:
        assert f.read().strip() == "230", "The aggregation result is incorrect."


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"C++ source {SOURCE_PATH} is missing."
    assert not os.path.islink(SOURCE_PATH), "The C++ source must be a regular file."
    assert os.path.getsize(SOURCE_PATH) > 0, "The C++ source is empty."

    assert os.path.isfile(BINARY_PATH), f"Compiled program {BINARY_PATH} is missing."
    assert not os.path.islink(BINARY_PATH), "The compiled program must be a regular file."
    assert os.access(BINARY_PATH, os.X_OK), "The compiled program is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled program is not an ELF executable."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", REBUILT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        "graph_etl.cpp does not compile:\n" + compile_result.stderr
    )

    # Restore the immutable input before execution so direct database edits made
    # before verification cannot satisfy the checks.
    reset_database()
    run_result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "The submitted graph_etl executable failed:\n" + run_result.stderr
    )
    assert_expected_fixed_state()

    # Also exercise a verifier-built copy so the submitted C++ source itself must
    # implement the ETL rather than merely accompanying an unrelated executable.
    reset_database()
    rebuilt_result = subprocess.run(
        [REBUILT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert rebuilt_result.returncode == 0, (
        "The program rebuilt from graph_etl.cpp failed:\n" + rebuilt_result.stderr
    )
    assert_expected_fixed_state()
    yield


def get_true_shortest_paths(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT id, weight FROM nodes")
    nodes = {row[0]: row[1] for row in cursor.fetchall()}

    cursor.execute("SELECT source, target FROM edges")
    edges = cursor.fetchall()

    adj = {u: [] for u in nodes}
    for u, v in edges:
        if u in adj:
            adj[u].append(v)

    def dijkstra(start):
        dist = {u: float('inf') for u in nodes}
        dist[start] = nodes[start]
        pq = [(nodes[start], start)]

        while pq:
            d, u = heapq.heappop(pq)
            if d > dist[u]:
                continue
            for v in adj.get(u, []):
                new_d = d + nodes[v]
                if new_d < dist[v]:
                    dist[v] = new_d
                    heapq.heappush(pq, (new_d, v))
        return dist

    shortest_paths = {}
    for start in nodes:
        shortest_paths[start] = dijkstra(start)

    conn.close()
    return shortest_paths


def test_database_updated_correctly():
    """Test that the materialized_paths table is correctly updated."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    true_paths = get_true_shortest_paths(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT source, target, total_weight, is_valid FROM materialized_paths")
    rows = cursor.fetchall()

    for source, target, total_weight, is_valid in rows:
        expected_weight = true_paths.get(source, {}).get(target, float('inf'))

        if expected_weight != float('inf'):
            assert is_valid == 1, f"Path {source}->{target} exists but is_valid is not 1."
            assert total_weight == expected_weight, f"Path {source}->{target} weight is {total_weight}, expected {expected_weight}."
        else:
            assert is_valid == 0, f"Path {source}->{target} does not exist but is_valid is not 0."

    conn.close()


def test_aggregation_result_file():
    """Test that the aggregation result file contains the correct sum."""
    assert os.path.exists(RESULT_PATH), f"Result file {RESULT_PATH} is missing."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"Result file content '{content}' is not a valid integer."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT SUM(total_weight) FROM materialized_paths WHERE is_valid = 1")
    expected_sum = cursor.fetchone()[0]
    conn.close()

    assert int(content) == expected_sum, f"Result file contains {content}, expected {expected_sum}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
