#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
import tempfile
import pytest


def run_script(script_path, db_path, user_id):
    try:
        result = subprocess.run(
            ["python3", script_path, db_path, str(user_id)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Executing the script failed: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Executing the script timed out.")

    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_result_file_exists_and_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    with open(result_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["David", "Eve", "Frank"]
    assert lines == expected, f"Expected {expected} in {result_path}, but got {lines}."


def test_script_fixed_dynamically():
    script_path = "/home/user/get_2nd_degree.py"
    db_path = "/home/user/graph.db"

    assert os.path.isfile(script_path), f"Python script {script_path} is missing."
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    output_lines = run_script(script_path, db_path, 2)
    expected_output = ["Grace"]
    assert output_lines == expected_output, (
        "The script did not return the correct 2nd degree connections for user_id=2. "
        f"Expected {expected_output}, got {output_lines}."
    )


def test_script_implements_general_second_degree_traversal():
    script_path = "/home/user/get_2nd_degree.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    rng = secrets.SystemRandom()
    node_count = 12
    names = {i: f"user_{secrets.token_hex(8)}" for i in range(1, node_count + 1)}

    # Build an unpredictable directed graph. Ring edges guarantee useful paths;
    # random edges, cycles, overlaps, and duplicate rows exercise exclusions and
    # duplicate elimination.
    edges = []
    for i in range(1, node_count + 1):
        edges.append((i, (i % node_count) + 1))
        edges.append((i, ((i + 1) % node_count) + 1))
    for source in range(1, node_count + 1):
        for target in range(1, node_count + 1):
            if source != target and rng.random() < 0.22:
                edges.append((source, target))
    for edge in rng.sample(edges, min(8, len(edges))):
        edges.append(edge)

    fd, generated_db = tempfile.mkstemp(prefix="graph_check_", suffix=".db")
    os.close(fd)
    try:
        conn = sqlite3.connect(generated_db)
        conn.executescript("""
            CREATE TABLE nodes (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            );
            CREATE TABLE edges (
                source INTEGER,
                target INTEGER,
                FOREIGN KEY(source) REFERENCES nodes(id),
                FOREIGN KEY(target) REFERENCES nodes(id)
            );
        """)
        conn.executemany(
            "INSERT INTO nodes (id, name) VALUES (?, ?)",
            list(names.items()),
        )
        conn.executemany("INSERT INTO edges (source, target) VALUES (?, ?)", edges)
        conn.commit()
        conn.close()

        adjacency = {i: set() for i in names}
        for source, target in edges:
            adjacency[source].add(target)

        # Test several unpredictable starting users and derive each answer from
        # the generated graph independently of the submitted script.
        tested_users = rng.sample(list(names), 6)
        for user_id in tested_users:
            direct = adjacency[user_id]
            second_hop = set()
            for friend_id in direct:
                second_hop.update(adjacency[friend_id])
            second_hop.discard(user_id)
            second_hop.difference_update(direct)
            expected = sorted({names[node_id] for node_id in second_hop})

            actual = run_script(script_path, generated_db, user_id)
            assert actual == expected, (
                f"Incorrect result for generated graph user_id={user_id}: "
                f"expected {expected}, got {actual}."
            )
    finally:
        if os.path.exists(generated_db):
            os.unlink(generated_db)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
