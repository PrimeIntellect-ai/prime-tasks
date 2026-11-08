#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import secrets
import subprocess
from pathlib import Path

import pytest

RUST_FILE = Path("/home/user/path_optimizer.rs")
OUTPUT_FILE = Path("/home/user/optimized_path.txt")
EDGES_FILE = Path("/home/user/graph_data/edges.csv")
BINARY = Path("/tmp/path_optimizer_verified")
EXPECTED_ORIGINAL = "NODE_START,B,NODE_END"


def test_rust_file_exists():
    """Verify that the Rust source file was created."""
    rust_file = "/home/user/path_optimizer.rs"
    assert os.path.isfile(rust_file), f"Rust source file {rust_file} is missing. You must create the Rust program."


def test_optimized_path_exists_and_correct():
    """Verify that the agent produced the correct output file."""
    output_file = "/home/user/optimized_path.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did you run the Rust program?"

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_path = "NODE_START,B,NODE_END"
    assert content == expected_path, (
        f"The computed path in {output_file} is incorrect.\n"
        f"Expected: '{expected_path}'\n"
        f"Got: '{content}'\n"
        "Ensure you are properly filtering out non-ACTIVE edges (like MAINTENANCE and OFFLINE) "
        "and computing the shortest path by total cost."
    )


def test_source_compiles_and_reproduces_original_result():
    """Compile the submitted Rust source and verify its freshly generated output."""
    assert RUST_FILE.stat().st_size > 0, "The Rust source file is empty."
    result = subprocess.run(
        ["rustc", str(RUST_FILE), "-o", str(BINARY)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"rustc failed:\n{result.stderr}"
    assert BINARY.is_file(), "rustc did not produce an executable."

    OUTPUT_FILE.unlink(missing_ok=True)
    result = subprocess.run([str(BINARY)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT_FILE.is_file(), "The compiled program did not create optimized_path.txt."
    assert OUTPUT_FILE.read_text().strip() == EXPECTED_ORIGINAL


def shortest_active_path(rows):
    graph = {}
    for source, target, cost, state in rows:
        if state == "ACTIVE":
            graph.setdefault(source, []).append((target, int(cost)))

    distances = {"NODE_START": 0}
    previous = {}
    queue = [(0, "NODE_START")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == "NODE_END":
            break
        for target, cost in graph.get(node, []):
            candidate = distance + cost
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert "NODE_END" in distances, "Verifier generated an unreachable graph."
    path = ["NODE_END"]
    while path[-1] != "NODE_START":
        path.append(previous[path[-1]])
    path.reverse()
    return ",".join(path)


def write_edges(rows):
    with EDGES_FILE.open("w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target", "cost", "state"])
        writer.writerows(rows)


def test_compiled_program_handles_changed_graphs():
    """Exercise the compiled artifact on unseen weighted graphs and derive each answer."""
    original_edges = EDGES_FILE.read_bytes()
    original_output = OUTPUT_FILE.read_bytes() if OUTPUT_FILE.exists() else None
    token = secrets.token_hex(6)
    a, b, c, d = [f"N_{token}_{name}" for name in ("A", "B", "C", "D")]

    cases = [
        [
            ("NODE_START", "NODE_END", 47, "ACTIVE"),
            ("NODE_START", a, 3, "ACTIVE"),
            (a, b, 4, "ACTIVE"),
            (b, "NODE_END", 2, "ACTIVE"),
            ("NODE_START", c, 5, "ACTIVE"),
            (c, "NODE_END", 19, "ACTIVE"),
            ("NODE_START", "NODE_END", 1, "MAINTENANCE"),
            (a, "NODE_END", 1, "OFFLINE"),
            (b, a, 1, "ACTIVE"),
        ],
        [
            ("NODE_START", a, 6, "ACTIVE"),
            (a, "NODE_END", 5, "ACTIVE"),
            ("NODE_START", b, 1, "ACTIVE"),
            (b, "NODE_END", 1, "OFFLINE"),
            (b, c, 3, "ACTIVE"),
            (c, d, 4, "ACTIVE"),
            (d, "NODE_END", 12, "ACTIVE"),
            ("NODE_START", "NODE_END", 2, "MAINTENANCE"),
            ("NODE_END", "NODE_START", 1, "ACTIVE"),
        ],
    ]

    try:
        for index, rows in enumerate(cases, 1):
            expected = shortest_active_path(rows)
            write_edges(rows)
            OUTPUT_FILE.unlink(missing_ok=True)
            result = subprocess.run([str(BINARY)], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, (
                f"Program failed on verification graph {index}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert OUTPUT_FILE.is_file(), (
                f"Program did not create optimized_path.txt for verification graph {index}."
            )
            actual = OUTPUT_FILE.read_text().strip()
            assert actual == expected, (
                f"Incorrect result for verification graph {index}. "
                f"Expected '{expected}', got '{actual}'."
            )
    finally:
        EDGES_FILE.write_bytes(original_edges)
        if original_output is None:
            OUTPUT_FILE.unlink(missing_ok=True)
        else:
            OUTPUT_FILE.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
