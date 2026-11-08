#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import secrets
import subprocess
import pytest

CPP_FILE = "/home/user/shortest_path.cpp"
EDGES_FILE = "/home/user/edges.csv"
OUTPUT_FILE = "/home/user/output.json"
BINARY = "/tmp/verifier_shortest_path"


def load_output():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. Did you compile and run your program?"
    with open(OUTPUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_FILE} does not contain valid JSON.")
    assert "path" in data, "JSON output is missing the 'path' key."
    assert "total_weight" in data, "JSON output is missing the 'total_weight' key."
    return data


def expected_from_csv():
    graph = {}
    with open(EDGES_FILE, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source", "target", "weight"]
        for row in reader:
            graph.setdefault(row["source"], []).append((row["target"], int(row["weight"])))

    queue = [(0, ["A"], "A")]
    best = {"A": 0}
    while queue:
        distance, path, node = heapq.heappop(queue)
        if distance != best.get(node):
            continue
        if node == "Z":
            return path, distance
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < best.get(target, float("inf")):
                best[target] = candidate
                heapq.heappush(queue, (candidate, path + [target], target))
    pytest.fail("The test graph has no path from A to Z.")


def run_program():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    subprocess.run([BINARY], check=True, timeout=10)
    return load_output()


def assert_matches_graph(data):
    expected_path, expected_weight = expected_from_csv()
    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data["total_weight"] == expected_weight, f"Expected total_weight {expected_weight}, but got {data['total_weight']}."


def test_cpp_program_and_output():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} is missing."

    # Preserve the original verifier's assertion about the output the agent left behind.
    initial = load_output()
    expected_path = ["A", "F", "G", "Z"]
    expected_weight = 11
    assert initial["path"] == expected_path, f"Expected path {expected_path}, but got {initial['path']}."
    assert initial["total_weight"] == expected_weight, f"Expected total_weight {expected_weight}, but got {initial['total_weight']}."

    subprocess.run(
        ["g++", "-O3", "-std=c++17", CPP_FILE, "-o", BINARY],
        check=True,
        timeout=30,
    )

    # Delete the pre-generated JSON and require the compiled submission to recreate it.
    original = run_program()
    assert_matches_graph(original)
    assert original["path"] == expected_path, f"Expected path {expected_path}, but got {original['path']}."
    assert original["total_weight"] == expected_weight, f"Expected total_weight {expected_weight}, but got {original['total_weight']}."

    with open(EDGES_FILE, "rb") as f:
        saved_edges = f.read()

    a = secrets.randbelow(9) + 1
    b = secrets.randbelow(9) + 1
    c = secrets.randbelow(9) + 1
    shortest = a + b + c
    alternate_graph = f"""source,target,weight
A,P,{a}
P,Q,{b}
Q,Z,{c}
A,Q,{a + b + 4}
P,Z,{b + c + 7}
A,R,{shortest + 5}
R,Z,1
A,Z,{shortest + 10}
R,Q,{shortest + 20}
"""

    try:
        with open(EDGES_FILE, "w") as f:
            f.write(alternate_graph)
        alternate = run_program()
        assert_matches_graph(alternate)
    finally:
        with open(EDGES_FILE, "wb") as f:
            f.write(saved_edges)
        # Leave output.json corresponding to the original input graph.
        subprocess.run([BINARY], check=True, timeout=10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
