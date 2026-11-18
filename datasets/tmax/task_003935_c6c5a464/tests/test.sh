#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import subprocess

import pytest

BASE = "/home/user/network_etl"
SOURCE = os.path.join(BASE, "process_graph.c")
RAW = os.path.join(BASE, "raw_routes.csv")
OUTPUT = os.path.join(BASE, "processed_nodes.csv")
BINARY = f"/tmp/process_graph_verifier_{os.getpid()}"

ORIGINAL_INPUT = """0,1,10
0,2,5
1,2,2
1,3,1
2,3,9
3,4,4
"""


def run_program(input_text):
    with open(RAW, "w", newline="") as f:
        f.write(input_text)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [BINARY],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."


def expected_output(edges):
    nodes = set()
    adjacency = {}
    degree = {}

    for a, b, weight in edges:
        nodes.update((a, b))
        adjacency.setdefault(a, []).append((b, weight))
        adjacency.setdefault(b, []).append((a, weight))
        degree[a] = degree.get(a, 0) + 1
        degree[b] = degree.get(b, 0) + 1

    distances = {node: float("inf") for node in nodes}
    if 0 in nodes:
        distances[0] = 0
        queue = [(0, 0)]
        while queue:
            distance, node = heapq.heappop(queue)
            if distance != distances[node]:
                continue
            for neighbor, weight in adjacency.get(node, []):
                candidate = distance + weight
                if candidate < distances[neighbor]:
                    distances[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))

    lines = ["NodeID,ShortestPathFrom0,Degree"]
    for node in sorted(nodes):
        distance = distances[node]
        rendered_distance = -1 if distance == float("inf") else int(distance)
        lines.append(f"{node},{rendered_distance},{degree[node]}")
    return lines


def read_output_lines():
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_original_fixture():
    assert os.path.isfile(SOURCE), f"Required C source file {SOURCE} is missing."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        f"{SOURCE} did not compile successfully.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable program."
    )

    run_program(ORIGINAL_INPUT)
    yield

    try:
        os.remove(BINARY)
    except FileNotFoundError:
        pass


def test_processed_nodes_file_exists():
    """Test that the processed_nodes.csv file exists."""
    file_path = "/home/user/network_etl/processed_nodes.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} was not created."


def test_processed_nodes_content():
    """Test that the processed_nodes.csv file has the correct content."""
    file_path = "/home/user/network_etl/processed_nodes.csv"

    expected_lines = [
        "NodeID,ShortestPathFrom0,Degree",
        "0,0,2",
        "1,7,3",
        "2,5,3",
        "3,8,3",
        "4,12,1"
    ]

    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]

    assert content == expected_lines, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(content)}"
    )


def test_program_handles_modified_graphs():
    rng = random.SystemRandom()

    labels = rng.sample(range(7, 180), 7)
    a, b, c, d, e, f, g = labels
    cases = [
        [
            (0, a, rng.randint(2, 25)),
            (0, b, rng.randint(2, 25)),
            (a, c, rng.randint(1, 12)),
            (b, c, rng.randint(1, 12)),
            (c, d, rng.randint(2, 20)),
            (a, d, rng.randint(15, 35)),
            (e, f, rng.randint(1, 20)),
            (f, g, rng.randint(1, 20)),
        ],
        [
            (0, g, rng.randint(1, 15)),
            (g, d, rng.randint(1, 15)),
            (0, c, rng.randint(10, 30)),
            (d, c, rng.randint(1, 8)),
            (c, a, rng.randint(1, 15)),
            (a, e, rng.randint(1, 15)),
            (d, b, rng.randint(1, 15)),
            (b, f, rng.randint(1, 15)),
            (e, f, rng.randint(5, 25)),
        ],
    ]

    for edges in cases:
        presented_edges = []
        for left, right, weight in edges:
            if rng.choice((True, False)):
                left, right = right, left
            presented_edges.append((left, right, weight))
        rng.shuffle(presented_edges)

        input_text = "".join(f"{a},{b},{w}\n" for a, b, w in presented_edges)
        run_program(input_text)

        actual = read_output_lines()
        expected = expected_output(edges)
        assert actual == expected, (
            "Program produced incorrect output for a modified valid graph.\n"
            f"Input:\n{input_text}"
            f"Expected:\n{chr(10).join(expected)}\n"
            f"Got:\n{chr(10).join(actual)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
