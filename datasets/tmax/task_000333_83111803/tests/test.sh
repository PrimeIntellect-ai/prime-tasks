#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import sqlite3
import stat
import subprocess
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/find_path.sh"
DB_PATH = "/home/user/dataset/citations.db"


def invoke(*args):
    return subprocess.run(
        [SCRIPT_PATH, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def parse_successful_result(result):
    assert result.returncode == 0, f"Script exited with non-zero status: {result.stderr}"
    assert result.stderr == "", f"Script produced unexpected stderr: {result.stderr!r}"
    output = result.stdout.strip()
    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        pytest.fail(f"Output is not valid JSON. Got: {output}")
    assert isinstance(data, list), f"Output must be a JSON array, got: {data!r}"
    assert all(type(item) is int for item in data), f"Path must contain only integer IDs: {data!r}"
    return data


def test_script_exists_and_executable():
    """Check if the find_path.sh script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f"Script at {SCRIPT_PATH} is not a regular file"
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable"


def test_is_bash_script_using_sqlite_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.match(r"^#![^\n]*\bbash\b", source), "find_path.sh must be a Bash script"
    noncomment = "\n".join(
        line for line in source.splitlines()
        if not re.match(r"^\s*#", line)
    )
    assert re.search(r"\bsqlite3\b", noncomment, re.IGNORECASE), \
        "The script must execute SQLite using the sqlite3 command"
    assert DB_PATH in source, f"The script must query {DB_PATH}"
    assert re.search(r"\bWITH\s+RECURSIVE\b", noncomment, re.IGNORECASE), \
        "The SQLite query must use a recursive CTE"


def test_requires_exactly_two_arguments():
    for args in [("101",), ("101", "105", "110")]:
        result = invoke(*args)
        assert result.returncode != 0, \
            f"Expected non-zero status for {len(args)} arguments, got stdout={result.stdout!r}"


def test_shortest_path_101_105():
    """Check if the script correctly finds the shortest path between 101 and 105."""
    data = parse_successful_result(invoke("101", "105"))
    assert data == [101, 108, 105], f"Expected path [101, 108, 105], but got {data}"


def test_unreachable_path_105_101():
    """Check if the script correctly handles unreachable paths."""
    data = parse_successful_result(invoke("105", "101"))
    assert data == [], f"Expected empty array [] for unreachable path, but got {data}"


def test_dead_end_path_101_110():
    """Check if the script correctly finds a path to a dead end."""
    data = parse_successful_result(invoke("101", "110"))
    assert data == [101, 109, 110], f"Expected path [101, 109, 110], but got {data}"


def shortest_distance(adjacency, source, target):
    queue = deque([(source, 0)])
    seen = {source}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for nxt in adjacency.get(node, ()):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, distance + 1))
    return None


def assert_shortest_valid_path(source, target, data, edge_set, adjacency):
    distance = shortest_distance(adjacency, source, target)
    if distance is None:
        assert data == [], f"Expected no path from {source} to {target}, got {data}"
        return
    assert data, f"Expected a path from {source} to {target}, got []"
    assert data[0] == source and data[-1] == target, \
        f"Path must start at {source} and end at {target}: {data}"
    assert all((a, b) in edge_set for a, b in zip(data, data[1:])), \
        f"Output contains a non-citation edge: {data}"
    assert len(data) - 1 == distance, \
        f"Path is not shortest: expected {distance} edges, got {len(data) - 1}: {data}"


def test_randomized_database_paths_are_computed_generally():
    rng = random.Random(secrets.randbits(128))
    base = rng.randrange(1_000_000, 1_900_000_000)
    nodes = [base + i for i in range(14)]

    # A randomized acyclic component with a guaranteed long route, shortcuts,
    # dead ends, and unreachable reverse-direction pairs.
    edges = {(nodes[i], nodes[i + 1]) for i in range(len(nodes) - 1)}
    for i in range(len(nodes)):
        for j in range(i + 2, len(nodes)):
            if rng.random() < 0.22:
                edges.add((nodes[i], nodes[j]))

    connection = sqlite3.connect(DB_PATH)
    try:
        connection.executemany(
            "INSERT INTO papers(id, title) VALUES (?, ?)",
            [(node, f"Verifier paper {i}") for i, node in enumerate(nodes)],
        )
        connection.executemany(
            "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
            list(edges),
        )
        connection.commit()

        rows = connection.execute("SELECT source_id, target_id FROM citations").fetchall()
        edge_set = set(rows)
        adjacency = {}
        for source, target in rows:
            adjacency.setdefault(source, set()).add(target)

        pairs = [
            (nodes[0], nodes[-1]),
            (nodes[1], nodes[10]),
            (nodes[3], nodes[12]),
            (nodes[6], nodes[7]),
            (nodes[-1], nodes[0]),
            (nodes[10], nodes[2]),
            (nodes[5], nodes[5]),
        ]
        for _ in range(4):
            a, b = sorted(rng.sample(range(len(nodes)), 2))
            pairs.append((nodes[a], nodes[b]))

        for source, target in pairs:
            data = parse_successful_result(invoke(source, target))
            assert_shortest_valid_path(source, target, data, edge_set, adjacency)
    finally:
        placeholders = ",".join("?" for _ in nodes)
        connection.execute(
            f"DELETE FROM citations WHERE source_id IN ({placeholders}) OR target_id IN ({placeholders})",
            nodes + nodes,
        )
        connection.execute(f"DELETE FROM papers WHERE id IN ({placeholders})", nodes)
        connection.commit()
        connection.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
