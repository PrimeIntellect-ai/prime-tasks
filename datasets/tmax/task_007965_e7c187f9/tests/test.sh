#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess

import pytest

SCRIPT = "/home/user/analyze.sh"
NETWORK = "/home/user/network.csv"
RESULT = "/home/user/result.json"


def run_script():
    if os.path.lexists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"analyze.sh exited with {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT), f"Missing output file after running script: {RESULT}"


def load_result():
    with open(RESULT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT} is not valid JSON")


def expected_for(edges):
    unique_edges = set(edges)
    nodes = {node for edge in unique_edges for node in edge}
    degrees = {
        node: sum(1 for source, _ in unique_edges if source == node)
        + sum(1 for _, target in unique_edges if target == node)
        for node in nodes
    }
    max_degree = max(degrees.values())
    central = min(node for node, degree in degrees.items() if degree == max_degree)

    direct = {target for source, target in unique_edges if source == central}
    foaf = {
        target2
        for source1, middle in unique_edges
        if source1 == central
        for source2, target2 in unique_edges
        if source2 == middle and target2 != central and target2 not in direct
    }
    return {"central_node": central, "foaf": sorted(foaf)}


def write_network(edges):
    with open(NETWORK, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target"])
        writer.writerows(edges)


@pytest.fixture(scope="module")
def original_run():
    assert os.path.isfile(SCRIPT), f"Missing required file: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"
    run_script()


def test_analyze_script_exists_and_executable():
    """Test that the analyze.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Missing required file: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"


def test_result_json_exists(original_run):
    """Test that result.json is freshly created by analyze.sh."""
    assert os.path.isfile(RESULT), f"Missing output file: {RESULT}"


def test_result_json_content(original_run):
    """Test the result for the provided network."""
    assert os.path.isfile(RESULT), f"Missing output file: {RESULT}"
    data = load_result()

    assert "central_node" in data, "JSON missing 'central_node' key"
    assert "foaf" in data, "JSON missing 'foaf' key"
    assert data["central_node"] == "Alice", f"Incorrect central node: {data['central_node']}"

    expected_foaf = ["Charlie", "Eve", "Frank"]
    assert isinstance(data["foaf"], list), "'foaf' must be a JSON array"
    assert data["foaf"] == expected_foaf, (
        f"Incorrect FOAF array: {data['foaf']} (expected {expected_foaf})"
    )


def test_script_computes_altered_networks(original_run):
    with open(NETWORK, "rb") as f:
        original_network = f.read()

    def names(count):
        return [f"N{secrets.token_hex(5)}" for _ in range(count)]

    # A deliberate degree tie tests alphabetical tie-breaking. Duplicate rows
    # verify that centrality counts unique edges.
    x, y, a, b, c, d, e, f, g, h = names(10)
    tie_case = [
        (x, a), (x, b), (c, x), (d, x), (a, c), (b, d),
        (y, e), (y, f), (g, y), (h, y), (e, g), (f, h),
        (x, a),
    ]

    # This case exercises exclusion of direct neighbors and the central node
    # itself from two-hop matches.
    p, q, r, s, t, u, v, w = names(8)
    exclusion_case = [
        (p, q), (p, r), (p, s), (t, p), (u, p), (r, p),
        (q, v), (q, r), (s, w), (p, q),
    ]

    # A runtime-generated graph prevents passing by hardcoding known answers.
    random_names = names(9)
    random_case = [
        (random_names[i], random_names[(i + 1) % len(random_names)])
        for i in range(len(random_names))
    ]
    rng = random.SystemRandom()
    pairs = [(a, b) for a in random_names for b in random_names if a != b]
    random_case.extend(rng.sample(pairs, 18))
    random_case.extend(random_case[:2])

    try:
        for edges in (tie_case, exclusion_case, random_case):
            write_network(edges)
            expected = expected_for(edges)
            run_script()
            data = load_result()

            assert "central_node" in data, "JSON missing 'central_node' key"
            assert "foaf" in data, "JSON missing 'foaf' key"
            assert isinstance(data["foaf"], list), "'foaf' must be a JSON array"
            assert data["central_node"] == expected["central_node"], (
                f"Incorrect central node for altered input: {data['central_node']} "
                f"(expected {expected['central_node']})"
            )
            assert data["foaf"] == expected["foaf"], (
                f"Incorrect FOAF array for altered input: {data['foaf']} "
                f"(expected {expected['foaf']})"
            )
    finally:
        with open(NETWORK, "wb") as f:
            f.write(original_network)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
