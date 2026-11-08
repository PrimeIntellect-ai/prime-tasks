#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.spatial.distance import jensenshannon

SCRIPT_PATH = "/home/user/simulate_diffusion.py"
NETWORK_PATH = "/home/user/ppi_network.csv"


def reference_simulate(graph_file, iterations=10):
    graph = {}
    with open(graph_file) as f:
        for line in f:
            u, v = line.strip().split(",")
            if u not in graph:
                graph[u] = set()
            if v not in graph:
                graph[v] = set()
            graph[u].add(v)
            graph[v].add(u)

    nodes = sorted(graph.keys())
    dist = {n: np.float32(1.0 / len(nodes)) for n in nodes}

    for _ in range(iterations):
        new_dist = {}
        for n in nodes:
            val = np.float32(0.0)
            for nbr in sorted(graph[n]):
                val = np.float32(val + np.float32(1e6))
                val = np.float32(val + dist[nbr])
                val = np.float32(val - np.float32(1e6))
            new_dist[n] = val

        total = sum(new_dist.values())
        if total > 0:
            dist = {n: new_dist[n] / total for n in nodes}
        else:
            dist = new_dist

    return {k: float(v) for k, v in dist.items()}


def parse_distribution(stdout):
    try:
        result = json.loads(stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Script output is not valid JSON: {exc}")
    assert isinstance(result, dict), "Script output must be a JSON object."
    assert result, "Script output must contain the network's node distribution."
    for key, value in result.items():
        assert isinstance(key, str), "Distribution node IDs must be strings."
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Probability for {key!r} is not numeric."
        assert math.isfinite(float(value)), f"Probability for {key!r} is not finite."
    return result


def run_cli(seed):
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = str(seed)
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            env=env,
            capture_output=True,
            text=True,
            check=True,
            cwd="/home/user",
            timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        stderr = getattr(exc, "stderr", "")
        pytest.fail(f"Execution of {SCRIPT_PATH} failed with PYTHONHASHSEED={seed}:\n{stderr}")
    return parse_distribution(result.stdout)


def run_simulate(graph_file, iterations, seed):
    helper = r'''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location("submitted_diffusion", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = module.simulate(sys.argv[2], iterations=int(sys.argv[3]))
print(json.dumps(result))
'''
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = str(seed)
    try:
        result = subprocess.run(
            ["python3", "-c", helper, SCRIPT_PATH, graph_file, str(iterations)],
            env=env,
            capture_output=True,
            text=True,
            check=True,
            cwd="/home/user",
            timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        stderr = getattr(exc, "stderr", "")
        pytest.fail(f"Calling simulate() on a verifier-generated network failed:\n{stderr}")
    return parse_distribution(result.stdout)


def assert_matches_reference(actual, expected):
    assert set(actual) == set(expected), \
        f"Output node IDs differ from the input network: got {sorted(actual)}, expected {sorted(expected)}"
    for node in sorted(expected):
        assert float(actual[node]) == pytest.approx(expected[node], rel=0.0, abs=1e-15), \
            f"Incorrect diffusion probability for node {node!r}"


def test_jsd_original():
    path = "/home/user/jsd_original.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: {content}")

    assert val > 0.0, f"JSD for original runs should be > 0, but got {val}"
    assert math.isfinite(val), "JSD for original runs must be finite."
    assert val <= math.sqrt(math.log(2.0)) + 1e-12, \
        f"Reported value {val} is outside the possible base-e Jensen-Shannon distance range."


def test_jsd_fixed():
    path = "/home/user/jsd_fixed.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: {content}")

    assert val == 0.0, f"JSD for fixed runs should be exactly 0.0, but got {val}"

    out1 = run_cli(1)
    out2 = run_cli(2)
    assert set(out1) == set(out2), "Fixed runs returned different node IDs."
    keys = sorted(out1)
    computed = float(jensenshannon(
        [float(out1[k]) for k in keys],
        [float(out2[k]) for k in keys],
    ))
    assert math.isfinite(computed), "JSD recomputed from the fixed outputs is not finite."
    assert val == computed, \
        f"{path} does not equal the JSD recomputed from two fixed-script runs: {computed}"


def test_simulate_diffusion_deterministic():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."

    out1 = run_cli(1)
    out2 = run_cli(2)
    assert out1 == out2, \
        "The output of simulate_diffusion.py is not deterministic across different PYTHONHASHSEED values."

    expected = reference_simulate(NETWORK_PATH)
    assert_matches_reference(out1, expected)


def test_diffusion_logic_on_verifier_generated_network():
    token = uuid.uuid4().hex
    nodes = [f"node_{token}_{i}" for i in range(8)]
    edge_indices = [
        (0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
        (1, 2), (1, 6), (2, 3), (2, 5), (2, 7),
        (3, 4), (3, 6), (4, 5), (4, 7), (5, 6), (6, 7),
    ]

    fd, graph_path = tempfile.mkstemp(prefix="diffusion_graph_", suffix=".csv")
    os.close(fd)
    try:
        with open(graph_path, "w") as f:
            for i, j in edge_indices:
                f.write(f"{nodes[i]},{nodes[j]}\n")

        expected = reference_simulate(graph_path, iterations=7)
        out1 = run_simulate(graph_path, 7, 17)
        out2 = run_simulate(graph_path, 7, 991)
        assert out1 == out2, \
            "simulate() is not deterministic on a verifier-generated network."
        assert_matches_reference(out1, expected)
    finally:
        os.unlink(graph_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
