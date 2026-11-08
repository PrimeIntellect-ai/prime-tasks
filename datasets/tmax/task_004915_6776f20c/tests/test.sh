#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import stat
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "mc_fit.go")
RESULT = os.path.join(HOME, "tvd_result.txt")
NETWORK = os.path.join(HOME, "network.json")
EXPERIMENTAL = os.path.join(HOME, "experimental_dist.json")
BINARY = "/tmp/mc_fit_submission"
RUNS = {}


def expected_stationary_tvd(graph, experimental):
    total_degree = sum(len(neighbors) for neighbors in graph.values())
    stationary = {
        node: len(neighbors) / total_degree
        for node, neighbors in graph.items()
    }
    nodes = set(stationary) | set(experimental)
    return 0.5 * sum(
        abs(stationary.get(node, 0.0) - experimental.get(node, 0.0))
        for node in nodes
    )


def run_case(graph, experimental):
    with open(NETWORK, "w") as f:
        json.dump(graph, f)
    with open(EXPERIMENTAL, "w") as f:
        json.dump(experimental, f)

    if os.path.exists(RESULT):
        os.remove(RESULT)

    subprocess.run([BINARY], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(RESULT), f"Failed: {RESULT} was not created by the Go program."

    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"(?:0|[1-9][0-9]*)\.[0-9]{4}", content), \
        f"Failed: result must be a nonnegative floating-point number rounded to 4 decimal places, got '{content}'"
    return content, float(content)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SOURCE), f"Failed: {SOURCE} not found. You must write your Go program to this file."
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Failed: {SOURCE} must be a regular Go source file."
    assert os.path.getsize(SOURCE) > 0, f"Failed: {SOURCE} is empty."

    subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd=HOME,
        check=True,
        timeout=60,
    )

    with open(NETWORK, "rb") as f:
        original_network_bytes = f.read()
    with open(EXPERIMENTAL, "rb") as f:
        original_experimental_bytes = f.read()
    original_graph = json.loads(original_network_bytes)
    original_experimental = json.loads(original_experimental_bytes)

    try:
        graph1 = {"A": ["B"], "B": ["A"]}
        dist1 = {"A": 0.5, "B": 0.5}
        RUNS["deterministic"] = (run_case(graph1, dist1), expected_stationary_tvd(graph1, dist1))

        graph2 = {"A": ["B"], "B": ["A", "C"], "C": ["B"]}
        dist2 = {"A": 0.1, "B": 0.2, "C": 0.7}
        RUNS["path"] = (run_case(graph2, dist2), expected_stationary_tvd(graph2, dist2))

        RUNS["original"] = (
            run_case(original_graph, original_experimental),
            expected_stationary_tvd(original_graph, original_experimental),
        )
        yield
    finally:
        with open(NETWORK, "wb") as f:
            f.write(original_network_bytes)
        with open(EXPERIMENTAL, "wb") as f:
            f.write(original_experimental_bytes)


def test_tvd_result_exists():
    assert os.path.exists(RESULT), f"Failed: {RESULT} not found. Ensure your Go program writes to this file."


def test_tvd_result_value():
    assert os.path.exists(RESULT), f"Failed: {RESULT} not found."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        assert False, f"Failed: The content of {RESULT} is not a valid float: '{content}'"
    assert 0.0480 <= val <= 0.0520, f"Failed: TVD {val} is not within the acceptable range (0.0480 - 0.0520). Check your random walk simulation logic and TVD calculation."


def test_go_source_exists():
    assert os.path.exists(SOURCE), f"Failed: {SOURCE} not found. You must write your Go program to this file."


def test_deterministic_walk_case():
    (_, actual), expected = RUNS["deterministic"]
    assert abs(actual - expected) <= 0.0001, \
        f"Failed deterministic walk case: expected TVD {expected:.4f}, got {actual:.4f}"


def test_nontrivial_walk_case():
    (_, actual), expected = RUNS["path"]
    assert abs(actual - expected) <= 0.0030, \
        f"Failed nontrivial walk case: expected TVD near {expected:.4f}, got {actual:.4f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
