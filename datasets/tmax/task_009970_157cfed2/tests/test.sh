#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import secrets
import subprocess

SCRIPT_PATH = "/home/user/analyze_graph.sh"
NETWORK_PATH = "/home/user/network.csv"
RESULT_PATH = "/home/user/result.txt"


def run_script():
    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Script exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )


def read_result():
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} does not exist. Did you run the script?"
    with open(RESULT_PATH, "r") as f:
        return f.read().strip().splitlines()


def expected_from_csv(path):
    adjacency = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source", "target", "weight"]
        for row in reader:
            source = row["source"]
            target = row["target"]
            weight = int(row["weight"])
            adjacency.setdefault(source, {})
            adjacency.setdefault(target, {})
            if target not in adjacency[source] or weight < adjacency[source][target]:
                adjacency[source][target] = weight
                adjacency[target][source] = weight

    central = sorted(adjacency, key=lambda node: (-len(adjacency[node]), node))[0]
    queue = [(0, central, [central])]
    best = {central: 0}
    while queue:
        distance, node, path = heapq.heappop(queue)
        if distance != best.get(node):
            continue
        if node == "Node_Z":
            return [
                f"Central Node: {central}",
                f"Shortest Path: {'->'.join(path)}",
                f"Total Weight: {distance}",
            ]
        for neighbor, weight in adjacency[node].items():
            new_distance = distance + weight
            if new_distance < best.get(neighbor, float("inf")):
                best[neighbor] = new_distance
                heapq.heappush(queue, (new_distance, neighbor, path + [neighbor]))
    raise AssertionError("Node_Z is unreachable in generated test graph")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_result_txt_content():
    run_script()
    expected_lines = [
        "Central Node: C",
        "Shortest Path: C->D->E->Node_Z",
        "Total Weight: 6"
    ]

    content = read_result()
    assert len(content) == 3, f"Expected 3 lines in {RESULT_PATH}, but found {len(content)}."

    for i, expected in enumerate(expected_lines):
        assert content[i].strip() == expected, f"Line {i+1} of {RESULT_PATH} is incorrect. Expected '{expected}', got '{content[i].strip()}'."


def test_script_analyzes_changed_graph():
    with open(NETWORK_PATH, "rb") as f:
        original_network = f.read()
    original_result = None
    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    labels = {
        name: "N_" + secrets.token_hex(5)
        for name in ["A", "B", "C", "D", "E", "F", "G"]
    }
    cd = random.randint(1, 3)
    de = random.randint(2, 4)
    ez = random.randint(1, 3)
    edges = [
        (labels["A"], labels["B"], random.randint(2, 6)),
        (labels["A"], labels["C"], random.randint(5, 9)),
        (labels["B"], labels["C"], random.randint(4, 7)),
        (labels["B"], labels["D"], random.randint(4, 7)),
        (labels["C"], labels["D"], cd),
        (labels["D"], labels["E"], de),
        (labels["C"], "Node_Z", cd + de + ez + random.randint(1, 5)),
        (labels["E"], "Node_Z", ez),
        (labels["C"], labels["F"], random.randint(1, 9)),
        (labels["C"], labels["G"], random.randint(1, 9)),
    ]
    edges = [
        (target, source, weight) if secrets.randbits(1) else (source, target, weight)
        for source, target, weight in edges
    ]
    random.SystemRandom().shuffle(edges)

    try:
        with open(NETWORK_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["source", "target", "weight"])
            writer.writerows(edges)

        expected_lines = expected_from_csv(NETWORK_PATH)
        run_script()
        content = read_result()
        assert len(content) == 3, f"Expected 3 lines in {RESULT_PATH}, but found {len(content)}."
        assert [line.strip() for line in content] == expected_lines, (
            f"Script did not correctly analyze the changed undirected graph. "
            f"Expected {expected_lines}, got {[line.strip() for line in content]}."
        )
    finally:
        with open(NETWORK_PATH, "wb") as f:
            f.write(original_network)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
