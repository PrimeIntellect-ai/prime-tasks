#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

PROGRAM = "/home/user/recovery.go"
NODES = Path("/home/user/nodes.csv")
EDGES = Path("/home/user/edges.csv")
OUTPUT = Path("/home/user/recovery_plan.txt")

CANONICAL_NODES = [
    ("s3_deep_archive", "storage", 1000),
    ("archive_tier2", "storage", 800),
    ("fast_restore_appliance", "appliance", 500),
    ("stage_db", "database", 200),
    ("prod_main_db", "database", 250),
    ("dr_standby", "database", 250),
]

CANONICAL_EDGES = [
    ("s3_deep_archive", "archive_tier2", 120),
    ("s3_deep_archive", "fast_restore_appliance", 30),
    ("fast_restore_appliance", "stage_db", 10),
    ("archive_tier2", "stage_db", 5),
    ("stage_db", "prod_main_db", 5),
    ("fast_restore_appliance", "prod_main_db", 25),
    ("stage_db", "dr_standby", 15),
]


def write_inputs(nodes, edges):
    for path in (NODES, EDGES):
        if path.is_symlink() or path.is_file():
            path.unlink()

    with NODES.open("w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "type", "size_gb"])
        writer.writerows(nodes)

    with EDGES.open("w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target", "restore_time_min"])
        writer.writerows(edges)

    os.chmod(NODES, 0o666)
    os.chmod(EDGES, 0o666)


def run_program():
    if OUTPUT.is_symlink() or OUTPUT.is_file():
        OUTPUT.unlink()
    elif OUTPUT.exists():
        pytest.fail(f"{OUTPUT} exists but is not a regular output file")

    try:
        result = subprocess.run(
            ["go", "run", PROGRAM],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("go run timed out after 30 seconds")

    assert result.returncode == 0, f"go run failed with output:\n{result.stdout}"


def reference_result(nodes, edges):
    sizes = {node_id: int(size) for node_id, _, size in nodes}
    graph = {node_id: [] for node_id in sizes}
    for source, target, weight in edges:
        graph.setdefault(source, []).append((target, int(weight)))

    start = "s3_deep_archive"
    target = "prod_main_db"
    distances = {start: 0}
    paths = {start: [start]}
    queue = [(0, start)]

    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == target:
            break
        for neighbor, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                paths[neighbor] = paths[node] + [neighbor]
                heapq.heappush(queue, (candidate, neighbor))

    assert target in distances, "Generated test graph unexpectedly has no path"
    path = paths[target]
    cumulative_size = sum(sizes[node] for node in path)
    return (
        f"Path: {' -> '.join(path)}\n"
        f"Total Time: {distances[target]} min\n"
        f"Cumulative Size: {cumulative_size} GB"
    )


def read_output():
    assert OUTPUT.is_file(), f"The output file {OUTPUT} is missing. Did the Go program run successfully?"
    return OUTPUT.read_text().strip()


def make_hidden_case(case_number):
    rng = random.SystemRandom()
    suffix = secrets.token_hex(6)
    start = "s3_deep_archive"
    target = "prod_main_db"

    optimal_middle = [f"optimal_{case_number}_{i}_{suffix}" for i in range(case_number + 2)]
    alternate = [f"alternate_{case_number}_{i}_{suffix}" for i in range(3)]
    dead_end = f"dead_end_{case_number}_{suffix}"
    optimal_path = [start] + optimal_middle + [target]

    node_ids = [start, target] + optimal_middle + alternate + [dead_end]
    nodes = [(node_id, "database", rng.randint(11, 997)) for node_id in node_ids]

    edges = []
    optimal_total = 0
    for source, destination in zip(optimal_path, optimal_path[1:]):
        weight = rng.randint(2, 9)
        optimal_total += weight
        edges.append((source, destination, weight))

    # A tempting direct edge and two slower restoration routes ensure the program
    # must use edge weights rather than hop count or CSV order.
    edges.append((start, target, optimal_total + rng.randint(15, 30)))
    first_weight = rng.randint(1, 8)
    edges.extend([
        (start, alternate[0], first_weight),
        (alternate[0], target, optimal_total + 12 - first_weight),
        (start, alternate[1], rng.randint(10, 15)),
        (alternate[1], alternate[2], rng.randint(10, 15)),
        (alternate[2], target, optimal_total + 20),
        (start, dead_end, 1),
        (optimal_middle[-1], optimal_middle[0], optimal_total + 40),
    ])

    rng.shuffle(nodes)
    rng.shuffle(edges)
    return nodes, edges


def test_go_program_exists():
    """Verify that the student wrote the Go program."""
    assert os.path.isfile(PROGRAM), f"The Go program {PROGRAM} is missing."
    mode = os.stat(PROGRAM, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"The Go program {PROGRAM} must be a regular file."
    assert os.path.getsize(PROGRAM) > 0, f"The Go program {PROGRAM} is empty."


def test_recovery_plan_output():
    """Compile and run the program, then retain the original exact output check."""
    write_inputs(CANONICAL_NODES, CANONICAL_EDGES)
    run_program()

    expected_output = (
        "Path: s3_deep_archive -> fast_restore_appliance -> stage_db -> prod_main_db\n"
        "Total Time: 45 min\n"
        "Cumulative Size: 1950 GB"
    )
    content = read_output()
    assert content == expected_output, (
        f"The content of {OUTPUT} is incorrect.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{content}"
    )


def test_program_parses_and_solves_hidden_graphs():
    """Exercise fresh CSV graphs whose expected answers are derived independently."""
    for case_number in range(3):
        nodes, edges = make_hidden_case(case_number)
        expected_output = reference_result(nodes, edges)
        write_inputs(nodes, edges)
        run_program()
        content = read_output()
        assert content == expected_output, (
            f"Incorrect result for generated graph {case_number}.\n"
            f"Expected:\n{expected_output}\n\nGot:\n{content}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
