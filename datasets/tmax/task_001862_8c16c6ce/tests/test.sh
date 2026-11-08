#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import secrets
import subprocess
import sys

import pytest

HOME = "/home/user"
RESULTS_PATH = os.path.join(HOME, "results.json")
TESTS_PATH = os.path.join(HOME, "tests.json")
ORCHESTRATOR_PATH = os.path.join(HOME, "test_orchestrator.py")

ORIGINAL_TESTS = [
    {
        "id": 1,
        "graph": {"A": [["B", 2], ["C", 3]], "B": [["C", 1]], "C": []},
        "start": "A",
        "expected": 3,
    },
    {
        "id": 2,
        "graph": {"X": [["Y", 5], ["Z", 2]], "Z": [["Y", 10]]},
        "start": "X",
        "expected": 12,
    },
    {
        "id": 3,
        "graph": {"M": [["N", 100]]},
        "start": "M",
        "expected": 100,
    },
]


def read_results():
    assert os.path.isfile(RESULTS_PATH), f"File not found: {RESULTS_PATH}"
    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON")
    assert isinstance(results, dict), "results.json must contain one JSON object"
    assert all(type(value) is bool for value in results.values()), "All result values must be booleans"
    return results


def write_tests(cases):
    with open(TESTS_PATH, "w") as f:
        json.dump(cases, f)


def run_orchestrator():
    assert os.path.isfile(ORCHESTRATOR_PATH), f"File not found: {ORCHESTRATOR_PATH}"
    if os.path.exists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)
    try:
        completed = subprocess.run(
            [sys.executable, ORCHESTRATOR_PATH],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("test_orchestrator.py timed out")
    assert completed.returncode == 0, (
        "test_orchestrator.py failed. stdout=%r stderr=%r"
        % (completed.stdout[-2000:], completed.stderr[-2000:])
    )
    return read_results()


def longest_path_oracle(graph, start):
    memo = {}

    def dfs(node):
        if node in memo:
            return memo[node]
        best = 0
        for neighbor, weight in graph.get(node, []):
            best = max(best, weight + dfs(neighbor))
        memo[node] = best
        return best

    return dfs(start)


def make_cases(rng, count):
    cases = []
    for index in range(count):
        size = rng.randint(1, 13)
        nodes = [f"n_{secrets.token_hex(5)}_{i}" for i in range(size)]
        graph = {}
        for i, node in enumerate(nodes):
            edges = []
            for j in range(i + 1, size):
                if rng.random() < 0.24:
                    edges.append([nodes[j], rng.randint(0, 40)])
            # Omit many leaves, including nodes reached by incoming edges.
            if edges or rng.random() < 0.55:
                graph[node] = edges
        start = nodes[rng.randrange(size)]
        actual = longest_path_oracle(graph, start)
        should_match = index % 5 != 2
        expected = actual if should_match else actual + rng.randint(1, 17)
        cases.append({
            "id": rng.randrange(10**8, 10**12),
            "graph": graph,
            "start": start,
            "expected": expected,
        })
    return cases


def test_results_json_exists_and_correct():
    results = read_results()
    expected_results = {"1": True, "2": True, "3": True}
    assert results == expected_results, (
        f"results.json does not match expected output. Got {results}, expected {expected_results}"
    )


def test_orchestrator_is_executed_and_handles_unseen_cases():
    assert os.path.isfile(ORCHESTRATOR_PATH), f"File not found: {ORCHESTRATOR_PATH}"

    # First execute the submitted orchestrator on the original shipped cases.
    write_tests(ORIGINAL_TESTS)
    original_results = run_orchestrator()
    assert original_results == {"1": True, "2": True, "3": True}

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    hidden_cases = make_cases(rng, 37)
    expected_results = {
        str(case["id"]): longest_path_oracle(case["graph"], case["start"]) == case["expected"]
        for case in hidden_cases
    }

    try:
        write_tests(hidden_cases)
        hidden_results = run_orchestrator()
        assert hidden_results == expected_results, (
            f"Orchestrator produced incorrect results for unseen cases: {hidden_results}"
        )
    finally:
        # Leave the required final artifacts corresponding to the original tests.
        write_tests(ORIGINAL_TESTS)
        subprocess.run(
            [sys.executable, ORCHESTRATOR_PATH],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )

    assert read_results() == {"1": True, "2": True, "3": True}


def test_algo_fixed():
    algo_path = "/home/user/algo.py"
    assert os.path.isfile(algo_path), f"File not found: {algo_path}"

    sys.path.insert(0, "/home/user")
    try:
        import algo
    except ImportError:
        pytest.fail("Could not import algo.py")

    try:
        # Test with a graph where the leaf node 'B' is not explicitly a key
        graph = {"A": [["B", 5]]}
        result = algo.longest_path(graph, "A")
        assert result == 5, f"Expected longest_path to return 5, but got {result}"
    except KeyError as e:
        pytest.fail(f"algo.longest_path raised KeyError: {e}. The bug is not fixed.")
    except Exception as e:
        pytest.fail(f"algo.longest_path raised an unexpected exception: {e}")


def test_algo_on_random_unseen_dags():
    import algo

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = make_cases(rng, 55)
    for case in cases:
        graph = copy.deepcopy(case["graph"])
        expected = longest_path_oracle(graph, case["start"])
        result = algo.longest_path(graph, case["start"])
        assert result == expected, (
            f"longest_path returned {result}, expected {expected} for "
            f"graph={graph!r}, start={case['start']!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
