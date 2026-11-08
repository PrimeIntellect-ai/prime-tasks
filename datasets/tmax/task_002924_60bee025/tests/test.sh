#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/graph_etl.c"
BINARY = "/tmp/graph_etl_verified"


def compile_program():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"graph_etl.c did not compile:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable."


def expected_distances(edges, start):
    nodes = set()
    adjacency = {}
    for source, target, weight in edges:
        nodes.add(source)
        nodes.add(target)
        # The C adjacency matrix uses the last weight for a repeated pair.
        adjacency[(source, target)] = weight

    graph = {node: [] for node in nodes}
    for (source, target), weight in adjacency.items():
        graph[source].append((target, weight))

    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for target, weight in graph[node]:
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))
    return distances


def run_program(edges, start):
    compile_program()
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="edges_", suffix=".txt") as edge_file:
        for source, target, weight in edges:
            edge_file.write(f"{source} {target} {weight}\n")
        edge_path = edge_file.name

    try:
        result = subprocess.run(
            [BINARY, edge_path, start],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    finally:
        os.unlink(edge_path)

    assert result.returncode == 0, f"Program failed for a valid graph:\n{result.stderr}"
    actual = {}
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        fields = line.strip().split("\t")
        assert len(fields) == 2, f"Malformed output line: {line!r}"
        node, distance_text = fields
        assert node not in actual, f"Node {node!r} was printed more than once."
        try:
            actual[node] = int(distance_text)
        except ValueError:
            raise AssertionError(f"Distance is not an integer in line: {line!r}")
    return actual


def test_output_tsv_exists():
    assert os.path.isfile("/home/user/output.tsv"), "/home/user/output.tsv does not exist. The program output must be saved to this file."


def test_output_tsv_content():
    expected_lines = [
        "A\t0",
        "C\t2",
        "B\t4",
        "D\t5",
        "E\t16"
    ]

    with open("/home/user/output.tsv", "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]

    assert lines == expected_lines, f"The contents of /home/user/output.tsv do not match the expected sorted output. Expected {expected_lines}, but got {lines}."


def test_graph_etl_c_modified():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    compile_program()

    edges = [
        ("S", "A", 7),
        ("X", "Y", 1),
        ("S", "B", 2),
        ("B", "C", 3),
        ("A", "C", 1),
        ("D", "E", 4),
    ]
    assert run_program(edges, "S") == expected_distances(edges, "S")


def test_program_on_original_input():
    edges = [
        ("A", "B", 4),
        ("A", "C", 2),
        ("B", "C", 5),
        ("B", "D", 10),
        ("C", "D", 3),
        ("D", "E", 11),
        ("E", "A", 8),
    ]
    assert run_program(edges, "A") == expected_distances(edges, "A")


def test_program_on_unseen_graphs():
    rng = secrets.SystemRandom()
    for case in range(4):
        reachable = [f"R{case}_{i}" for i in range(7)]
        disconnected = [f"U{case}_{i}" for i in range(3)]
        edges = []

        # Ensure every node is present while keeping two directed components.
        for i in range(len(reachable) - 1):
            edges.append((reachable[i], reachable[i + 1], rng.randint(1, 20)))
        for i in range(len(disconnected) - 1):
            edges.append((disconnected[i], disconnected[i + 1], rng.randint(1, 20)))

        for group in (reachable, disconnected):
            for _ in range(12):
                source = rng.choice(group)
                target = rng.choice(group)
                if source != target:
                    edges.append((source, target, rng.randint(1, 30)))

        rng.shuffle(edges)
        start = reachable[0]
        assert run_program(edges, start) == expected_distances(edges, start)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
