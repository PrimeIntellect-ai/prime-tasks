#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_graph.sh"
RESULTS_PATH = "/home/user/results.json"
GRAPH_PATH = "/home/user/graph.txt"
LABELS_PATH = "/home/user/labels.txt"
EXPECTED_KEYS = {
    "mean_degree",
    "std_degree",
    "slope",
    "intercept",
    "critical_threshold",
}

CANONICAL_GRAPH = """1 2
1 3
2 3
3 4
4 5
"""
CANONICAL_LABELS = """1 0.10
2 0.20
3 0.80
4 0.30
5 0.05
"""


def write_inputs(graph_text, labels_text):
    with open(GRAPH_PATH, "w") as f:
        f.write(graph_text)
    with open(LABELS_PATH, "w") as f:
        f.write(labels_text)


def run_script():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, \
        f"Script failed to execute. STDERR: {result.stderr}"
    assert os.path.isfile(RESULTS_PATH), \
        f"File {RESULTS_PATH} was not created by the script."

    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")


def assert_values(data, expected_values):
    for key, expected in expected_values.items():
        assert key in data, f"Key '{key}' is missing from the JSON output."
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
            f"Value for '{key}' must be a number."
        assert math.isfinite(actual), f"Value for '{key}' must be finite."
        assert math.isclose(actual, expected, abs_tol=1e-4), \
            f"Value for '{key}' is {actual}, expected {expected} (rounded to 4 decimal places)."


def derive_expected(nodes, edges, labels):
    degrees = {node: 0 for node in nodes}
    for u, v in edges:
        if u in degrees:
            degrees[u] += 1
        if v in degrees:
            degrees[v] += 1

    xs = [degrees[node] for node in nodes]
    ys = [labels[node] for node in nodes]
    n = len(nodes)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    variance = sum((x - mean_x) ** 2 for x in xs) / n
    std_degree = math.sqrt(variance)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / \
        sum((x - mean_x) ** 2 for x in xs)
    intercept = mean_y - slope * mean_x
    threshold = (0.5 - intercept) / slope

    return {
        "mean_degree": round(mean_x, 4),
        "std_degree": round(std_degree, 4),
        "slope": round(slope, 4),
        "intercept": round(intercept, 4),
        "critical_threshold": round(threshold, 4),
    }


def make_random_case():
    rng = secrets.SystemRandom()
    n = rng.randint(7, 10)
    nodes = rng.sample(range(100, 5000), n)

    # Connect all but the final node in a path, leaving one labeled node isolated.
    # Add random simple edges so degrees vary from run to run.
    edge_set = {
        tuple(sorted((nodes[i], nodes[i + 1]))) for i in range(n - 2)
    }
    for i in range(n - 1):
        for j in range(i + 2, n - 1):
            if rng.random() < 0.38:
                edge_set.add(tuple(sorted((nodes[i], nodes[j]))))
    edges = list(edge_set)

    degrees = {node: 0 for node in nodes}
    for u, v in edges:
        degrees[u] += 1
        degrees[v] += 1

    beta = rng.uniform(0.13, 0.47)
    alpha = rng.uniform(-0.35, 0.25)
    labels = {
        node: alpha + beta * degrees[node] + rng.uniform(-0.025, 0.025)
        for node in nodes
    }

    graph_lines = []
    rng.shuffle(edges)
    for u, v in edges:
        if rng.random() < 0.5:
            u, v = v, u
        graph_lines.append(f"{u} {v}")

    label_order = list(nodes)
    rng.shuffle(label_order)
    label_lines = [f"{node} {labels[node]:.10f}" for node in label_order]

    # Expected values are derived from the exact decimal labels written to disk.
    written_labels = {node: float(f"{labels[node]:.10f}") for node in nodes}
    return (
        "\n".join(graph_lines) + "\n",
        "\n".join(label_lines) + "\n",
        derive_expected(nodes, edges, written_labels),
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_results():
    write_inputs(CANONICAL_GRAPH, CANONICAL_LABELS)
    data = run_script()

    expected_values = {
        "mean_degree": 2.0000,
        "std_degree": 0.6325,
        "slope": 0.3750,
        "intercept": -0.4600,
        "critical_threshold": 2.5600,
    }
    assert_values(data, expected_values)


def test_script_computes_from_runtime_inputs():
    try:
        # Multiple unpredictable cases prevent passing by emitting constants for
        # the graph and labels installed by setup.
        for _ in range(3):
            graph_text, labels_text, expected = make_random_case()
            write_inputs(graph_text, labels_text)
            data = run_script()
            assert_values(data, expected)
    finally:
        write_inputs(CANONICAL_GRAPH, CANONICAL_LABELS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
