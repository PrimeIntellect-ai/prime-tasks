#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

PROJECT_PATH = "/home/user/graph_tool"
DB_PATH = os.path.join(PROJECT_PATH, "graph.db")
OUTPUT_PATH = os.path.join(PROJECT_PATH, "output.json")
SOURCE_PATH = os.path.join(PROJECT_PATH, "src", "main.rs")
BINARY_PATH = os.path.join(PROJECT_PATH, "target", "debug", "graph_tool")

ORIGINAL_EDGES = [
    ("START", "A"),
    ("A", "B"),
    ("B", "C"),
    ("C", "END"),
    ("START", "X"),
    ("X", "Y"),
    ("Y", "END"),
    ("START", "M"),
    ("M", "END"),
    ("M", "NOPE"),
]


def read_edges():
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute("SELECT source, target FROM edges").fetchall()


def replace_edges(edges):
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DELETE FROM edges")
        conn.executemany("INSERT INTO edges(source, target) VALUES (?, ?)", edges)
        conn.commit()


def run_program():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Rust program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Program did not create {OUTPUT_PATH}."
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Program produced invalid JSON: {exc}")


def shortest_path(edges):
    adjacency = collections.defaultdict(list)
    for source, target in edges:
        adjacency[source].append(target)
    queue = collections.deque([("START", ["START"])])
    seen = {"START"}
    while queue:
        node, path = queue.popleft()
        if node == "END":
            return path
        for target in adjacency[node]:
            if target not in seen:
                seen.add(target)
                queue.append((target, path + [target]))
    return None


def assert_output(data, expected_path):
    assert isinstance(data, dict), "Output JSON must be an object."
    assert "path" in data, "'path' key is missing in the JSON output."
    assert "hops" in data, "'hops' key is missing in the JSON output."
    assert data["path"] == expected_path, (
        f"Incorrect shortest path. Expected {expected_path}, got {data['path']}."
    )
    assert data["hops"] == len(expected_path) - 1, (
        f"Incorrect hops count. Expected {len(expected_path) - 1}, got {data['hops']}."
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_exercise_rust_program():
    assert os.path.isfile(SOURCE_PATH), f"Rust source file {SOURCE_PATH} not found."
    with open(SOURCE_PATH, "r") as f:
        source = f.read()

    # Ignore Rust comments so a comment alone cannot satisfy the recursive-CTE requirement.
    source_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source_without_comments = re.sub(r"//[^\n]*", "", source_without_comments)
    assert re.search(r"\bWITH\s+RECURSIVE\b", source_without_comments, re.IGNORECASE), (
        "src/main.rs does not contain a WITH RECURSIVE SQL query."
    )

    assert collections.Counter(read_edges()) == collections.Counter(ORIGINAL_EDGES), (
        "The original edges data was modified before verification."
    )

    build = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        f"Cargo build failed.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), "Cargo did not produce the graph_tool executable."
    assert os.access(BINARY_PATH, os.X_OK), "Built graph_tool artifact is not executable."

    original_expected = shortest_path(ORIGINAL_EDGES)
    assert_output(run_program(), original_expected)
    assert collections.Counter(read_edges()) == collections.Counter(ORIGINAL_EDGES), (
        "The Rust program modified the original edges data."
    )

    token = uuid.uuid4().hex
    short_mid = f"short_{token}"
    long_a = f"long_a_{token}"
    long_b = f"long_b_{token}"
    dead = f"dead_{token}"
    variant_edges = [
        ("START", long_a),
        (long_a, long_b),
        (long_b, "END"),
        ("START", short_mid),
        (short_mid, "END"),
        (long_a, dead),
    ]
    variant_expected = shortest_path(variant_edges)

    try:
        replace_edges(variant_edges)
        assert_output(run_program(), variant_expected)
    finally:
        replace_edges(ORIGINAL_EDGES)

    # Leave both the database and output in the required final state.
    assert_output(run_program(), original_expected)
    assert collections.Counter(read_edges()) == collections.Counter(ORIGINAL_EDGES), (
        "The Rust program modified the edges data."
    )


def test_database_index_created():
    """Verify that an index on the 'source' column of the 'edges' table was created."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} not found."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA index_list('edges');")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No index found on the 'edges' table."

    has_source_index = False
    for idx in indexes:
        idx_name = idx[1]
        cursor.execute(f"PRAGMA index_info('{idx_name}');")
        columns = cursor.fetchall()
        if any(col[2] == 'source' for col in columns):
            has_source_index = True
            break

    assert has_source_index, "No index found covering the 'source' column of the 'edges' table."
    conn.close()


def test_output_json_correctness():
    """Verify that the output.json file exists and contains the correct shortest path."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} not found."

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert "path" in data, "'path' key is missing in the JSON output."
    assert "hops" in data, "'hops' key is missing in the JSON output."

    expected_path = ["START", "M", "END"]
    expected_hops = 2

    assert data["path"] == expected_path, f"Incorrect shortest path. Expected {expected_path}, got {data['path']}."
    assert data["hops"] == expected_hops, f"Incorrect hops count. Expected {expected_hops}, got {data['hops']}."


def test_database_data_unmodified():
    """Verify that the original data in the 'edges' table was not modified."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} not found."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM edges;")
    count = cursor.fetchone()[0]
    assert count == 10, f"Expected 10 rows in the 'edges' table, but found {count}. The data was modified."

    cursor.execute("SELECT source, target FROM edges;")
    rows = cursor.fetchall()
    assert collections.Counter(rows) == collections.Counter(ORIGINAL_EDGES), (
        "The contents of the edges table differ from the original data."
    )

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
