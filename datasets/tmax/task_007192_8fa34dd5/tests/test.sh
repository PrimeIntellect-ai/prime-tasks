#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import pytest

GRAPH_PATH = "/home/user/graph.edges"
SOURCE_PATH = "/home/user/simulate.go"
CSV_PATH = "/home/user/final_phases.csv"


def expected_phases(graph_text):
    adj = {}
    for raw_line in graph_text.splitlines():
        parts = raw_line.split()
        if len(parts) != 2:
            continue
        u, v = map(int, parts)
        adj.setdefault(u, []).append(v)
        adj.setdefault(v, []).append(u)

    assert adj, "Test graph has no nodes."
    nodes = sorted(adj)
    max_degree = max(len(adj[n]) for n in nodes)
    K = 2.0
    T = 2.0
    omega = 1.0
    dt = 0.1 / (K * max_degree)
    steps = int(T / dt)
    phases = {n: float(n) * 0.1 for n in nodes}

    for _ in range(steps):
        new_phases = {}
        for i in nodes:
            coupling = sum(math.sin(phases[j] - phases[i]) for j in adj[i])
            new_phases[i] = phases[i] + dt * (omega + K * coupling)
        phases = new_phases

    return nodes, phases


def run_and_check(graph_text, tolerance):
    with open(GRAPH_PATH, "w") as f:
        f.write(graph_text)

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run(
        ["go", "run", SOURCE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"Simulation failed:\n{result.stdout}"
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} was not generated."

    with open(CSV_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_nodes, expected_values = expected_phases(graph_text)
    assert len(lines) == len(expected_nodes), (
        f"Expected {len(expected_nodes)} lines in {CSV_PATH}, got {len(lines)}."
    )

    actual_nodes = []
    actual_values = {}
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid line format in {CSV_PATH}: '{line}'"
        try:
            node_id = int(parts[0])
            phase = float(parts[1])
        except ValueError:
            pytest.fail(f"Could not parse node_id or phase as numbers in line: '{line}'")

        assert not math.isnan(phase), f"Phase for node {node_id} is NaN."
        assert not math.isinf(phase), f"Phase for node {node_id} is Inf."
        assert node_id in expected_values, f"Unexpected node_id {node_id} in output."
        assert node_id not in actual_values, f"Duplicate node_id {node_id} in output."

        actual_nodes.append(node_id)
        actual_values[node_id] = phase

    assert actual_nodes == expected_nodes, (
        f"Node IDs must be unique and sorted; got {actual_nodes}, expected {expected_nodes}."
    )

    for node_id in expected_nodes:
        phase = actual_values[node_id]
        expected_phase = expected_values[node_id]
        assert abs(phase - expected_phase) < tolerance, (
            f"Phase for node {node_id} is {phase}, expected approx {expected_phase}."
        )


def test_fixed_simulation_and_final_phases():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is missing."
    with open(GRAPH_PATH, "r") as f:
        original_graph = f.read()

    # A second valid topology ensures dt is derived from max_degree rather than
    # merely replacing 0.5 with a constant suitable only for the supplied graph.
    alternate_graph = "0 1\n1 2\n2 3\n3 4\n4 5\n"

    try:
        run_and_check(alternate_graph, tolerance=0.00001)
        # Run the supplied graph last so the required training data remains in place.
        run_and_check(original_graph, tolerance=0.01)
    finally:
        with open(GRAPH_PATH, "w") as f:
            f.write(original_graph)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
