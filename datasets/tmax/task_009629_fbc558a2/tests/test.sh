#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import shutil
import subprocess

import pytest

CPP_PATH = "/home/user/workspace/verify_backup.cpp"
REPORT_PATH = "/home/user/workspace/report.json"
NODES_PATH = "/home/user/backup/nodes.csv"
EDGES_PATH = "/home/user/backup/edges.csv"
BINARY_PATH = "/tmp/verify_backup_test"

ORIGINAL_NODES = [
    (1, "User"),
    (2, "User"),
    (3, "User"),
    (4, "Post"),
    (5, "Post"),
    (6, "User"),
    (7, "Page"),
]
ORIGINAL_EDGES = [
    (1, 2, "KNOWS"),
    (2, 3, "KNOWS"),
    (3, 4, "LIKES"),
    (2, 4, "LIKES"),
    (1, 5, "LIKES"),
    (6, 2, "KNOWS"),
    (6, 7, "LIKES"),
    (1, 6, "KNOWS"),
]


def write_fixture(nodes, edges):
    with open(NODES_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "label"])
        writer.writerows(nodes)
    with open(EDGES_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target", "type"])
        writer.writerows(edges)


def expected_results(nodes, edges):
    labels = {node_id: label for node_id, label in nodes}
    out_degree = {node_id: 0 for node_id, _ in nodes}
    outgoing = {}
    for source, target, edge_type in edges:
        out_degree[source] = out_degree.get(source, 0) + 1
        outgoing.setdefault(source, []).append((target, edge_type))

    highest = min(out_degree, key=lambda node_id: (-out_degree[node_id], node_id))
    count = 0
    for source, middle, edge_type in edges:
        if edge_type != "KNOWS":
            continue
        if labels.get(source) != "User" or labels.get(middle) != "User":
            continue
        for target, second_type in outgoing.get(middle, []):
            if second_type == "LIKES" and labels.get(target) == "Post":
                count += 1
    return highest, count


def run_and_read_report():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user/workspace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    try:
        with open(REPORT_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON: {exc}")

    assert set(data) == {"highest_out_degree_node", "pattern_match_count"}, (
        "report.json must contain exactly the required two keys."
    )
    assert type(data["highest_out_degree_node"]) is int
    assert type(data["pattern_match_count"]) is int
    return data


@pytest.fixture(scope="session", autouse=True)
def preserve_inputs_and_compile():
    saved = {}
    for path in (NODES_PATH, EDGES_PATH):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
    try:
        yield
    finally:
        for path, contents in saved.items():
            with open(path, "wb") as f:
                f.write(contents)
        if os.path.exists(BINARY_PATH):
            os.remove(BINARY_PATH)


def test_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."


def test_report_json_exists_and_valid():
    subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", BINARY_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    write_fixture(ORIGINAL_NODES, ORIGINAL_EDGES)
    data = run_and_read_report()

    assert "highest_out_degree_node" in data, "Key 'highest_out_degree_node' missing from report.json."
    assert "pattern_match_count" in data, "Key 'pattern_match_count' missing from report.json."
    assert data["highest_out_degree_node"] == 1, (
        f"Expected highest_out_degree_node to be 1, got {data['highest_out_degree_node']}."
    )
    assert data["pattern_match_count"] == 3, (
        f"Expected pattern_match_count to be 3, got {data['pattern_match_count']}."
    )


def test_program_computes_results_for_additional_inputs():
    fixtures = [
        (
            [(40, "User"), (7, "User"), (22, "Post")],
            [(40, 7, "KNOWS"), (7, 22, "LIKES")],
        ),
        (
            [(101, "User"), (205, "User"), (309, "User"), (404, "Post")],
            [
                (101, 205, "KNOWS"),
                (101, 205, "KNOWS"),
                (205, 404, "LIKES"),
                (205, 404, "LIKES"),
                (309, 205, "KNOWS"),
            ],
        ),
        (
            [(9, "Page"), (3, "User"), (80, "Post"), (14, "User")],
            [(9, 3, "KNOWS"), (14, 9, "LIKES"), (3, 14, "KNOWS")],
        ),
    ]

    rng = random.SystemRandom()
    for _ in range(4):
        ids = rng.sample(range(1000, 9000), 8)
        nodes = [(node_id, "User") for node_id in ids[:4]]
        nodes += [(node_id, "Post") for node_id in ids[4:7]]
        nodes += [(ids[7], "Page")]
        edges = [
            (ids[0], ids[1], "KNOWS"),
            (ids[1], ids[4], "LIKES"),
        ]
        edge_types = ["KNOWS", "LIKES", "FOLLOWS"]
        for _ in range(rng.randint(15, 28)):
            edges.append((rng.choice(ids), rng.choice(ids), rng.choice(edge_types)))
        fixtures.append((nodes, edges))

    for nodes, edges in fixtures:
        write_fixture(nodes, edges)
        expected_node, expected_count = expected_results(nodes, edges)
        data = run_and_read_report()
        assert data["highest_out_degree_node"] == expected_node, (
            f"Expected highest_out_degree_node {expected_node}, "
            f"got {data['highest_out_degree_node']}."
        )
        assert data["pattern_match_count"] == expected_count, (
            f"Expected pattern_match_count {expected_count}, "
            f"got {data['pattern_match_count']}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
