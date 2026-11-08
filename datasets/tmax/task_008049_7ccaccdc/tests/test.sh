#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path

import pytest

GRAPH_PATH = Path("/home/user/molecule_graph.txt")
VIS_PATH = Path("/home/user/visualization.txt")
SUMMARY_PATH = Path("/home/user/decomposition_summary.log")
SOURCE_PATH = Path("/home/user/decompose.c")
EXECUTABLE_PATH = Path("/home/user/decompose")
COMPILED_SOURCE_PATH = Path("/tmp/decompose_from_source")

ORIGINAL_NODES = [
    (0, -1.0, 0.0, 0.0),
    (1, -2.0, 1.0, 0.0),
    (2, -0.5, -1.0, 0.0),
    (3, 0.5, 1.0, 0.0),
    (4, 1.5, 0.5, 0.0),
    (5, 2.0, -0.5, 0.0),
    (6, -1.5, -1.5, 0.0),
    (7, 0.1, -0.1, 0.0),
    (8, 1.0, 2.0, 0.0),
    (9, -3.0, 0.0, 0.0),
]
ORIGINAL_EDGES = [
    (0, 1), (0, 2), (1, 9), (1, 6), (2, 6), (3, 4),
    (4, 5), (3, 8), (0, 3), (2, 7), (7, 5),
]


def write_graph(nodes, edges):
    with GRAPH_PATH.open("w") as f:
        f.write(f"NODES {len(nodes)}\n")
        for node_id, x, y, z in nodes:
            f.write(f"{node_id} {x:.8f} {y:.8f} {z:.8f}\n")
        f.write(f"EDGES {len(edges)}\n")
        for first, second in edges:
            f.write(f"{first} {second}\n")


def expected_outputs(nodes, edges):
    domains = {node_id: (0 if x < 0.0 else 1) for node_id, x, _, _ in nodes}
    degrees = {node_id: 0 for node_id, _, _, _ in nodes}
    cross_domain = 0
    for first, second in edges:
        degrees[first] += 1
        degrees[second] += 1
        if domains[first] != domains[second]:
            cross_domain += 1

    domain_zero = [node_id for node_id in degrees if domains[node_id] == 0]
    max_degree = max(degrees[node_id] for node_id in domain_zero)
    selected = min(node_id for node_id in domain_zero if degrees[node_id] == max_degree)
    count_zero = sum(domain == 0 for domain in domains.values())
    count_one = len(nodes) - count_zero

    visualization = [
        f"Domain 0: {'*' * (count_zero // 2)}",
        f"Domain 1: {'*' * (count_one // 2)}",
    ]
    summary = [
        f"Cross-domain edges: {cross_domain}",
        f"Max degree node in domain 0: {selected}",
    ]
    return visualization, summary


def execute(binary):
    VIS_PATH.unlink(missing_ok=True)
    SUMMARY_PATH.unlink(missing_ok=True)
    subprocess.run(
        [str(binary)],
        cwd="/home/user",
        check=True,
        timeout=10,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_and_check(binary, nodes, edges):
    write_graph(nodes, edges)
    expected_visualization, expected_summary = expected_outputs(nodes, edges)
    execute(binary)

    assert VIS_PATH.is_file(), f"{binary} did not create {VIS_PATH}."
    assert SUMMARY_PATH.is_file(), f"{binary} did not create {SUMMARY_PATH}."
    assert VIS_PATH.read_text().splitlines() == expected_visualization
    assert SUMMARY_PATH.read_text().splitlines() == expected_summary


def test_c_source_exists():
    """Test that the C source code file exists."""
    file_path = "/home/user/decompose.c"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    file_path = "/home/user/decompose"
    assert os.path.exists(file_path), f"The executable {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."
    assert os.access(file_path, os.X_OK), f"The file {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {file_path} is not a compiled executable."


def test_execute_on_original_graph():
    write_graph(ORIGINAL_NODES, ORIGINAL_EDGES)
    execute(EXECUTABLE_PATH)


def test_visualization_content():
    """Test that visualization.txt contains the correct ASCII bar chart."""
    file_path = "/home/user/visualization.txt"
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in {file_path}, found {len(lines)}."
    assert lines[0] == "Domain 0: **", f"Incorrect output for Domain 0. Got: {lines[0]}"
    assert lines[1] == "Domain 1: **", f"Incorrect output for Domain 1. Got: {lines[1]}"


def test_summary_report_content():
    """Test that decomposition_summary.log contains the correct analysis results."""
    file_path = "/home/user/decomposition_summary.log"
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {file_path}, found {len(lines)}."
    assert lines[0] == "Cross-domain edges: 2", f"Incorrect cross-domain edge count. Got: {lines[0]}"
    assert lines[1] == "Max degree node in domain 0: 0", f"Incorrect max degree node. Got: {lines[1]}"


def test_source_compiles():
    subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE_PATH), "-o", str(COMPILED_SOURCE_PATH)],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert COMPILED_SOURCE_PATH.is_file()
    assert os.access(COMPILED_SOURCE_PATH, os.X_OK)


def make_random_graph(rng):
    n = rng.randint(8, 16)
    negative_count = rng.randint(2, n - 2)
    negative_ids = set(rng.sample(range(n), negative_count))
    nodes = []
    for node_id in range(n):
        magnitude = rng.uniform(0.1, 9.0)
        x = -magnitude if node_id in negative_ids else magnitude
        nodes.append((node_id, x, rng.uniform(-5.0, 5.0), rng.uniform(-5.0, 5.0)))

    edges = []
    for first in range(n):
        for second in range(first + 1, n):
            if rng.random() < 0.28:
                edges.append((first, second))
    if not edges:
        edges.append((0, 1))
    return nodes, edges


def test_binaries_parse_and_compute_generated_graphs():
    rng = random.SystemRandom()
    tie_nodes = [
        (0, -1.0, 0.0, 0.0), (1, -2.0, 0.0, 0.0),
        (2, -3.0, 0.0, 0.0), (3, 0.0, 0.0, 0.0),
        (4, 1.0, 0.0, 0.0), (5, 2.0, 0.0, 0.0),
        (6, 3.0, 0.0, 0.0),
    ]
    tie_edges = [(0, 3), (0, 1), (1, 4), (2, 5), (2, 6)]
    cases = [(tie_nodes, tie_edges)] + [make_random_graph(rng) for _ in range(3)]

    try:
        for binary in (EXECUTABLE_PATH, COMPILED_SOURCE_PATH):
            for nodes, edges in cases:
                run_and_check(binary, nodes, edges)
    finally:
        write_graph(ORIGINAL_NODES, ORIGINAL_EDGES)
        subprocess.run(
            [str(EXECUTABLE_PATH)], cwd="/home/user", timeout=10,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
