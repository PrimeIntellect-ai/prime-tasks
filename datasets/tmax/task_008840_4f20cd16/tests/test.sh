#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import re
import secrets
import subprocess
import sys

SCRIPT = "/home/user/network_sim.py"
FINAL_LOSS = "/home/user/final_loss.txt"


def load_submission():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_network_sim", SCRIPT)
    assert spec is not None and spec.loader is not None, "network_sim.py is not importable"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "NetworkSimulation"), "NetworkSimulation is missing"
    return module.NetworkSimulation


def reference_final_loss():
    random.seed(42)
    num_nodes = 20
    edges = set()
    for i in range(num_nodes):
        for j in range(i + 1, num_nodes):
            if random.random() < 0.3:
                edges.add((i, j, random.uniform(0.1, 5.0)))

    capacities = [random.uniform(1.0, 10.0) for _ in range(num_nodes)]
    targets = [5.0 for _ in range(num_nodes)]
    for _ in range(50):
        for i in range(num_nodes):
            gradient = 2 * (capacities[i] - targets[i])
            capacities[i] -= 0.05 * gradient

    ordered = sorted(edges, key=lambda edge: (edge[0], edge[1]))
    return sum(weight for _, _, weight in ordered) + sum(
        (capacity - target) ** 2
        for capacity, target in zip(capacities, targets)
    )


def make_order_sensitive_case(axis):
    """Create a set for which set-order summation differs from required order."""
    rng = secrets.SystemRandom()
    for _ in range(2000):
        count = rng.randrange(18, 40)
        offset = rng.randrange(1000, 1000000)
        huge_at = rng.randrange(count)
        edges = set()
        for position in range(count):
            if axis == "target":
                source, target = offset, offset + position
            else:
                source, target = offset + position, offset
            # Positive weights match the domain of the supplied simulation while
            # making floating-point reduction order observably significant.
            weight = 1.0e16 if position == huge_at else float(rng.randrange(1, 5))
            edges.add((source, target, weight))

        required = sum(w for _, _, w in sorted(edges, key=lambda e: (e[0], e[1])))
        unordered = sum(w for _, _, w in edges)
        if required != unordered:
            return edges, required
    raise AssertionError("Could not construct an order-sensitive edge set")


def test_network_sim_updated_source_checks():
    # Preserve the original source-level assertions in addition to behavioral tests.
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    with open(SCRIPT, "r") as handle:
        content = handle.read()
    assert "sorted(" in content or ".sort(" in content, \
        "The script does not appear to sort the edges to fix the determinism issue."
    assert "capacities" in content, "The script is missing references to capacities."


def test_compute_total_loss_uses_source_then_target_order():
    cls = load_submission()

    # Independently exercise both ordering components with dynamically selected,
    # order-sensitive data. Comments or a hardcoded main result cannot satisfy this.
    for axis in ("source", "target"):
        edges, expected = make_order_sensitive_case(axis)
        sim = cls.__new__(cls)
        sim.num_nodes = 0
        sim.edges = edges
        sim.capacities = []
        sim.target_capacities = []
        actual = sim.compute_total_loss()
        assert actual == expected, (
            "compute_total_loss must sum edges after sorting by source and then target; "
            f"expected {expected!r}, got {actual!r}"
        )

    # Also verify edge and node losses are combined correctly on ordinary data.
    rng = secrets.SystemRandom()
    for _ in range(8):
        edges = {
            (rng.randrange(0, 200), rng.randrange(200, 400), rng.uniform(0.1, 5.0))
            for _ in range(35)
        }
        capacities = [rng.uniform(-20.0, 20.0) for _ in range(13)]
        targets = [rng.uniform(-10.0, 10.0) for _ in capacities]
        expected = sum(w for _, _, w in sorted(edges, key=lambda e: (e[0], e[1])))
        expected += sum((c - t) ** 2 for c, t in zip(capacities, targets))

        sim = cls.__new__(cls)
        sim.num_nodes = len(capacities)
        sim.edges = edges
        sim.capacities = capacities[:]
        sim.target_capacities = targets[:]
        assert sim.compute_total_loss() == expected


def test_gradient_descent_on_derived_inputs():
    cls = load_submission()
    rng = secrets.SystemRandom()

    cases = [(0, 0.05), (1, 0.1), (7, 0.03), (23, 0.2)]
    for epochs, learning_rate in cases:
        capacities = [rng.uniform(-30.0, 30.0) for _ in range(rng.randrange(3, 25))]
        targets = [rng.uniform(-15.0, 15.0) for _ in capacities]
        expected = capacities[:]
        for _ in range(epochs):
            for i in range(len(expected)):
                gradient = 2 * (expected[i] - targets[i])
                expected[i] -= learning_rate * gradient

        sim = cls.__new__(cls)
        sim.num_nodes = len(capacities)
        sim.edges = set()
        sim.capacities = capacities[:]
        sim.target_capacities = targets[:]
        sim.optimize_node_capacities(epochs=epochs, learning_rate=learning_rate)
        assert sim.capacities == expected, (
            "optimize_node_capacities did not perform the required gradient descent updates"
        )

    # Verify the provided default arguments as well.
    capacities = [rng.uniform(1.0, 10.0) for _ in range(11)]
    targets = [rng.uniform(2.0, 8.0) for _ in capacities]
    expected = capacities[:]
    for _ in range(50):
        for i in range(len(expected)):
            expected[i] -= 0.05 * 2 * (expected[i] - targets[i])
    sim = cls.__new__(cls)
    sim.num_nodes = len(capacities)
    sim.edges = set()
    sim.capacities = capacities[:]
    sim.target_capacities = targets[:]
    sim.optimize_node_capacities()
    assert sim.capacities == expected


def test_supplied_regression_script_and_main_execute():
    regression = subprocess.run(
        [sys.executable, "/home/user/test_sim.py"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert regression.returncode == 0, regression.stdout + regression.stderr

    main_run = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert main_run.returncode == 0, main_run.stdout + main_run.stderr
    match = re.search(r"Final Loss:\s*([^\s]+)", main_run.stdout)
    assert match, "Executing network_sim.py did not print its final loss"
    printed_loss = float(match.group(1))
    assert f"{printed_loss:.6f}" == f"{reference_final_loss():.6f}"


def test_final_loss_value():
    # Preserve the original exact fixed-seed output assertion.
    expected_str = f"{reference_final_loss():.6f}"
    assert os.path.exists(FINAL_LOSS), (
        f"File {FINAL_LOSS} does not exist. The task requires saving the final loss here."
    )
    with open(FINAL_LOSS, "r") as handle:
        actual_str = handle.read().strip()
    assert actual_str == expected_str, (
        f"Expected final loss to be exactly '{expected_str}', but got '{actual_str}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
