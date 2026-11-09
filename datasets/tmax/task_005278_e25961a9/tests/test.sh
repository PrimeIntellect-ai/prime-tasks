#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import stat
import subprocess
import sys

import pytest
import requests

URL = "http://127.0.0.1:8080/calculate"
DAMPING = 0.85
TOLERANCE = 1e-7


def reference_pagerank(graph):
    nodes = list(graph.keys())
    ranks = {node: 1.0 / len(nodes) for node in nodes}

    for iteration in range(1000):
        new_ranks = {}
        diff = 0.0
        for node in nodes:
            rank_sum = 0.0
            for in_node, out_edges in graph.items():
                if node in out_edges:
                    rank_sum += ranks[in_node] / len(out_edges)
            new_ranks[node] = (1.0 - DAMPING) / len(nodes) + DAMPING * rank_sum
            diff += abs(new_ranks[node] - ranks[node])
        ranks = new_ranks
        if diff < TOLERANCE:
            return ranks, iteration + 1

    return ranks, 1000


def request_ranks(graph):
    try:
        response = requests.post(URL, json={"graph": graph}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the PageRank service at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "ranks" in data, "Response JSON missing 'ranks' key"
    assert "iterations" in data, "Response JSON missing 'iterations' key"
    assert isinstance(data["ranks"], dict), "'ranks' must be a JSON object"
    assert isinstance(data["iterations"], int) and not isinstance(data["iterations"], bool), (
        "'iterations' must be an integer"
    )
    return data["ranks"], data["iterations"]


def check_graph(graph, retain_original_tolerance=False):
    expected, expected_iterations = reference_pagerank(graph)
    ranks, iterations = request_ranks(graph)

    assert set(ranks) == set(graph), "Returned rank keys must exactly match graph nodes"
    for node, value in ranks.items():
        assert isinstance(value, (int, float)) and not isinstance(value, bool), (
            f"Rank for node {node} is not numeric"
        )
        assert math.isfinite(value), f"Rank for node {node} is not finite"

    total_rank = sum(ranks.values())
    assert abs(total_rank - 1.0) < 1e-4, f"Sum of ranks should be ~1.0, got {total_rank}"

    # Preserve the original verifier's value assertions on its original graph.
    tolerance = 1e-4 if retain_original_tolerance else 2e-7
    for node, expected_val in expected.items():
        assert node in ranks, f"Node {node} missing from returned ranks"
        actual_val = ranks[node]
        assert abs(actual_val - expected_val) < tolerance, (
            f"Rank for node {node} is incorrect. Expected ~{expected_val:.10f}, "
            f"got {actual_val:.10f}. Check damping, tolerance, precision, and update math."
        )

    assert iterations == expected_iterations, (
        f"Incorrect iteration count: expected {expected_iterations}, got {iterations}. "
        "The solver must use tolerance 1e-7 without float truncation."
    )


def test_submission_file_and_configured_constants():
    path = "/app/pagerank.py"
    assert os.path.exists(path), f"Required server artifact {path} does not exist"
    assert stat.S_ISREG(os.stat(path).st_mode), f"{path} must be a regular Python file"

    probe = r'''
import importlib.util, json
spec = importlib.util.spec_from_file_location("submitted_pagerank", "/app/pagerank.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print("PARAMETERS=" + json.dumps({"damping": module.DAMPING, "tolerance": module.TOLERANCE}))
'''
    try:
        result = subprocess.run(
            [sys.executable, "-c", probe], text=True, capture_output=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Importing /app/pagerank.py timed out")

    assert result.returncode == 0, (
        f"Could not load /app/pagerank.py to inspect its parameters: {result.stderr}"
    )
    parameter_lines = [
        line for line in result.stdout.splitlines() if line.startswith("PARAMETERS=")
    ]
    assert parameter_lines, "Could not read DAMPING and TOLERANCE from /app/pagerank.py"
    params = json.loads(parameter_lines[-1].split("=", 1)[1])
    assert params["damping"] == DAMPING, "DAMPING must be exactly 0.85"
    assert params["tolerance"] == TOLERANCE, "TOLERANCE must be exactly 1e-7"


def test_pagerank_service_on_original_and_unpredictable_graphs():
    original = {"0": ["1", "2"], "1": ["2"], "2": ["0"]}
    check_graph(original, retain_original_tolerance=True)

    # Generate fresh node labels and graph structures at verification time so a
    # server cannot pass by recognizing and hardcoding a fixed test graph.
    rng = random.SystemRandom()
    tested = 0
    attempts = 0
    while tested < 8 and attempts < 100:
        attempts += 1
        size = rng.randint(3, 8)
        nonce = rng.getrandbits(64)
        nodes = [f"node_{nonce:x}_{i}" for i in range(size)]
        graph = {}
        for source in nodes:
            edges = [target for target in nodes if rng.random() < 0.38]
            if not edges:
                edges = [rng.choice(nodes)]
            graph[source] = edges

        _, expected_iterations = reference_pagerank(graph)
        # Avoid trivial symmetric cases that do not exercise convergence.
        if expected_iterations <= 3:
            continue
        check_graph(graph)
        tested += 1

    assert tested == 8, "Failed to generate enough nontrivial PageRank test graphs"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
