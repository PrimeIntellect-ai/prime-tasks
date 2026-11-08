#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import secrets
import subprocess


def test_cleaned_edges_csv():
    file_path = "/home/user/cleaned_edges.csv"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read()

    assert "CROSS_JOIN_ERROR" not in content, "The cleaned_edges.csv file still contains 'CROSS_JOIN_ERROR' lines."
    assert "NODE_001,NODE_100" in content, "The cleaned_edges.csv file is missing valid edges."

    with open("/home/user/network_edges.csv", "r") as f:
        expected = "".join(line for line in f if "CROSS_JOIN_ERROR" not in line)
    assert content == expected, "cleaned_edges.csv is not the complete filtered form of network_edges.csv."


def test_shortest_path_script():
    file_path = "/home/user/shortest_path.py"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."
    assert os.access(file_path, os.X_OK), f"The script {file_path} is not executable."


def test_result_txt():
    file_path = "/home/user/result.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Expected result.txt to contain '4', but found '{content}'."


def shortest_distance(edges):
    graph = collections.defaultdict(list)
    for source, target, _weight in edges:
        graph[source].append(target)
    queue = collections.deque([("NODE_001", 0)])
    seen = {"NODE_001"}
    while queue:
        node, distance = queue.popleft()
        if node == "NODE_999":
            return distance
        for neighbor in graph[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    raise AssertionError("Verifier generated an unreachable graph")


def test_script_executes_and_computes_dynamic_graphs():
    cleaned_path = "/home/user/cleaned_edges.csv"
    result_path = "/home/user/result.txt"
    script_path = "/home/user/shortest_path.py"
    with open(cleaned_path, "rb") as f:
        original_cleaned = f.read()
    with open(result_path, "rb") as f:
        original_result = f.read()

    rng = random.SystemRandom()
    hop_counts = [1, 2, 6, 9]
    rng.shuffle(hop_counts)

    try:
        for hops in hop_counts:
            tag = secrets.token_hex(8)
            internal = [f"NODE_PATH_{tag}_{i}" for i in range(max(0, hops - 1))]
            path = ["NODE_001"] + internal + ["NODE_999"]
            edges = []

            for i in range(len(path) - 1):
                edges.append((path[i], path[i + 1], str(rng.randint(1, 99))))
                edges.append((path[i + 1], path[i], str(rng.randint(1, 99))))

            alternate = [f"NODE_ALT_{tag}_{i}" for i in range(hops + 1)]
            alternate_path = ["NODE_001"] + alternate + ["NODE_999"]
            for i in range(len(alternate_path) - 1):
                edges.append((alternate_path[i], alternate_path[i + 1], str(rng.randint(1, 99))))

            decoys = [f"NODE_DECOY_{tag}_{i}" for i in range(30)]
            for i in range(len(decoys) - 1):
                edges.append((decoys[i], decoys[i + 1], str(rng.randint(1, 99))))
            edges.extend([
                ("NODE_999", decoys[0], "1"),
                (decoys[-1], "NODE_001", "1"),
            ])
            rng.shuffle(edges)

            expected = shortest_distance(edges)
            assert expected == hops
            with open(cleaned_path, "w") as f:
                for source, target, weight in edges:
                    f.write(f"{source},{target},{weight}\n")

            if os.path.exists(result_path):
                os.unlink(result_path)
            completed = subprocess.run(
                [script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert completed.returncode == 0, (
                f"shortest_path.py failed with exit code {completed.returncode}: "
                f"{completed.stderr}"
            )
            assert os.path.isfile(result_path), "shortest_path.py did not create result.txt."
            with open(result_path, "r") as f:
                actual = f.read().strip()
            assert actual == str(expected), (
                f"Expected dynamic shortest-path result {expected}, but found {actual!r}."
            )
    finally:
        with open(cleaned_path, "wb") as f:
            f.write(original_cleaned)
        with open(result_path, "wb") as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
