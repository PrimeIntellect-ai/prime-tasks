#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest

SCRIPT_PATH = "/home/user/solve_linking.sh"
DEPS_PATH = "/home/user/deps.json"
OUTPUT_PATH = "/home/user/link_order.txt"


def read_order():
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def expected_order(graph):
    incoming = {name: 0 for name in graph}
    for name, data in graph.items():
        for dep in data["deps"]:
            assert dep in graph, f"Test graph references unknown library {dep}"
            incoming[dep] += 1

    result = []
    remaining = set(graph)
    while remaining:
        eligible = [name for name in remaining if incoming[name] == 0]
        assert eligible, "Verifier generated a cyclic graph"
        chosen = max(eligible, key=lambda name: graph[name]["weight"])
        result.append(chosen)
        remaining.remove(chosen)
        for dep in graph[chosen]["deps"]:
            incoming[dep] -= 1
    return result


def run_script_for_graph(graph):
    with open(DEPS_PATH, "w") as f:
        json.dump(graph, f, sort_keys=True)
        f.write("\n")

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    completed = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"The script failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"The script did not create {OUTPUT_PATH} when executed."
    )
    return read_order()


def test_solve_linking_script_exists():
    script_path = "/home/user/solve_linking.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist. Did you create it?"
    completed = subprocess.run(
        ["bash", "-n", script_path], text=True, capture_output=True
    )
    assert completed.returncode == 0, f"The Bash script has a syntax error: {completed.stderr}"


def test_link_order_file_exists():
    output_path = "/home/user/link_order.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist. Did you run your script?"


def test_link_order_contents():
    output_path = "/home/user/link_order.txt"
    if not os.path.exists(output_path):
        pytest.fail(f"Cannot check contents because {output_path} is missing.")

    expected_order_value = [
        "libMain",
        "libMatrix",
        "libVector",
        "libMath",
        "libIO",
        "libCore"
    ]

    with open(output_path, "r") as f:
        actual_order = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_order == expected_order_value, (
        f"The linking order in {output_path} is incorrect.\n"
        f"Expected: {expected_order_value}\n"
        f"Actual:   {actual_order}"
    )


def test_script_computes_orders_for_changed_graphs():
    with open(DEPS_PATH, "rb") as f:
        original_deps = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    graphs = [
        json.loads(original_deps.decode("utf-8")),
        {
            "alpha": {"deps": ["delta"], "weight": -5},
            "beta": {"deps": ["delta", "epsilon"], "weight": 70},
            "gamma": {"deps": ["epsilon"], "weight": 20},
            "delta": {"deps": ["zeta"], "weight": 100},
            "epsilon": {"deps": ["zeta"], "weight": 4},
            "zeta": {"deps": [], "weight": -20},
        },
    ]

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for case in range(4):
        names = [f"node_{case}_{i}" for i in range(8)]
        weights = rng.sample(range(-200, 401), len(names))
        graph = {
            name: {"deps": [], "weight": weights[i]}
            for i, name in enumerate(names)
        }
        for i, name in enumerate(names):
            for j in range(i + 1, len(names)):
                if rng.random() < 0.30:
                    graph[name]["deps"].append(names[j])
        if not any(data["deps"] for data in graph.values()):
            graph[names[0]]["deps"].append(names[-1])
        graphs.append(graph)

    try:
        for graph in graphs:
            expected = expected_order(graph)
            actual = run_script_for_graph(graph)
            assert actual == expected, (
                "The script produced an incorrect order for a changed dependency graph.\n"
                f"Graph: {graph}\nExpected: {expected}\nActual:   {actual}"
            )
    finally:
        with open(DEPS_PATH, "wb") as f:
            f.write(original_deps)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
