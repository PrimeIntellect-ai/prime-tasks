#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import uuid

import pytest

ROOTS_FILE = "/home/user/roots.txt"
CYCLES_FILE = "/home/user/cycles.txt"
SCRIPT_FILE = "/home/user/analyze_graph.sh"
DB_FILE = "/home/user/etl_graph.db"

EXPECTED_ROOTS = [
    "extract_inventory",
    "extract_orders",
    "extract_users",
    "job_A"
]

EXPECTED_CYCLES = [
    "job_B",
    "job_C",
    "job_X",
    "job_Y",
    "job_Z"
]


def remove_outputs():
    for path in (ROOTS_FILE, CYCLES_FILE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_script():
    subprocess.run(
        [SCRIPT_FILE],
        cwd="/home/user",
        check=True,
        timeout=20,
    )


def read_lines(path):
    assert os.path.isfile(path), f"Output file missing at {path}"
    with open(path, "r") as f:
        return f.read().strip().splitlines()


def derive_expected(edges):
    nodes = {node for edge in edges for node in edge}
    targets = {target for _, target in edges}
    roots = sorted(nodes - targets)

    adjacency = {node: [] for node in nodes}
    for source, target in edges:
        adjacency[source].append(target)

    cyclic = []
    for start in nodes:
        stack = list(adjacency[start])
        seen = set()
        while stack:
            node = stack.pop()
            if node == start:
                cyclic.append(start)
                break
            if node not in seen:
                seen.add(node)
                stack.extend(adjacency.get(node, ()))

    return roots, sorted(cyclic)


def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_FILE), f"Script missing at {SCRIPT_FILE}"
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script at {SCRIPT_FILE} is not executable"


@pytest.fixture(scope="module")
def generated_original_outputs():
    remove_outputs()
    run_script()


def test_roots_file_content(generated_original_outputs):
    """Test that the roots.txt file contains the correct root jobs."""
    assert os.path.isfile(ROOTS_FILE), f"Roots file missing at {ROOTS_FILE}"

    with open(ROOTS_FILE, "r") as f:
        content = f.read().strip().splitlines()

    assert content == EXPECTED_ROOTS, f"Roots file content is incorrect. Expected {EXPECTED_ROOTS}, got {content}"


def test_cycles_file_content(generated_original_outputs):
    """Test that the cycles.txt file contains the correct cyclic jobs."""
    assert os.path.isfile(CYCLES_FILE), f"Cycles file missing at {CYCLES_FILE}"

    with open(CYCLES_FILE, "r") as f:
        content = f.read().strip().splitlines()

    assert content == EXPECTED_CYCLES, f"Cycles file content is incorrect. Expected {EXPECTED_CYCLES}, got {content}"


def test_script_queries_current_database(generated_original_outputs):
    token = "verify_" + uuid.uuid4().hex
    dynamic_edges = [
        (token + "_root1", token + "_linear1"),
        (token + "_linear1", token + "_linear2"),
        (token + "_root2", token + "_leaf"),
        (token + "_cycle_a", token + "_cycle_b"),
        (token + "_cycle_b", token + "_cycle_c"),
        (token + "_cycle_c", token + "_cycle_a"),
        (token + "_pair_a", token + "_pair_b"),
        (token + "_pair_b", token + "_pair_a"),
        (token + "_self", token + "_self"),
        (token + "_cycle_c", token + "_downstream"),
    ]
    expected_roots, expected_cycles = derive_expected(dynamic_edges)

    with sqlite3.connect(DB_FILE) as connection:
        original_edges = connection.execute(
            "SELECT source, target FROM dependencies"
        ).fetchall()

    try:
        with sqlite3.connect(DB_FILE) as connection:
            connection.execute("DELETE FROM dependencies")
            connection.executemany(
                "INSERT INTO dependencies(source, target) VALUES (?, ?)",
                dynamic_edges,
            )

        remove_outputs()
        run_script()

        assert read_lines(ROOTS_FILE) == expected_roots
        assert read_lines(CYCLES_FILE) == expected_cycles
    finally:
        with sqlite3.connect(DB_FILE) as connection:
            connection.execute("DELETE FROM dependencies")
            connection.executemany(
                "INSERT INTO dependencies(source, target) VALUES (?, ?)",
                original_edges,
            )
        remove_outputs()
        run_script()

    assert read_lines(ROOTS_FILE) == EXPECTED_ROOTS
    assert read_lines(CYCLES_FILE) == EXPECTED_CYCLES
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
