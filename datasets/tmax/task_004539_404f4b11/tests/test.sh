#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import pytest

SOURCE = "/home/user/deadlock_analyzer.cpp"
EXECUTABLE = "/home/user/deadlock_analyzer"
CSV_PATH = "/home/user/tx_locks.csv"
REPORT_PATH = "/home/user/deadlock_report.json"
COMPILED_TEST_EXECUTABLE = "/tmp/deadlock_analyzer_from_source"


def validate_report(expected):
    assert os.path.isfile(REPORT_PATH), f"Output JSON file {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON: {exc}")

    assert isinstance(data, dict), "JSON root must be an object."
    assert "deadlocks" in data, "JSON must contain a 'deadlocks' key at the root."
    deadlocks = data["deadlocks"]
    assert isinstance(deadlocks, list), "'deadlocks' must be an array."
    for cycle in deadlocks:
        assert isinstance(cycle, list), "Each deadlock must be an array."
        assert cycle, "Deadlock cycles must not be empty."
        assert all(isinstance(tx, str) for tx in cycle), "Transaction IDs must be strings."
        assert cycle == sorted(cycle), f"Cycle {cycle} is not sorted alphabetically."

    assert deadlocks == sorted(deadlocks, key=lambda cycle: cycle[0]), (
        "The 'deadlocks' array is not sorted alphabetically by the first element of each cycle."
    )

    normalized_actual = sorted(tuple(cycle) for cycle in deadlocks)
    normalized_expected = sorted(tuple(cycle) for cycle in expected)
    assert normalized_actual == normalized_expected, (
        f"Detected deadlocks do not match the expected cycles.\n"
        f"Expected: {normalized_expected}\nGot: {normalized_actual}"
    )


def expected_from_csv(path):
    holders = {}
    waiting = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["status"] == "GRANTED":
                holders.setdefault(row["resource_id"], set()).add(row["tx_id"])
            elif row["status"] == "WAITING":
                waiting.append((row["tx_id"], row["resource_id"]))

    graph = {}
    for tx, resource in waiting:
        graph.setdefault(tx, set()).update(holders.get(resource, set()))

    # Enumerate simple directed cycles, then apply the task's required
    # representation: alphabetically sorted transaction IDs per cycle.
    normalized_cycles = set()
    for start in list(graph):
        def dfs(node, path, seen):
            for neighbor in graph.get(node, set()):
                if neighbor == start:
                    normalized_cycles.add(tuple(sorted(path)))
                elif neighbor not in seen:
                    dfs(neighbor, path + [neighbor], seen | {neighbor})
        dfs(start, [start], {start})

    return [list(cycle) for cycle in sorted(normalized_cycles)]


def write_graph_fixture(nodes, edges):
    resources = {tx: f"RES_{i}_{secrets.token_hex(3)}" for i, tx in enumerate(nodes)}
    rows = []
    timestamp = 2000
    for tx in nodes:
        rows.append([timestamp, tx, resources[tx], "GRANTED"])
        timestamp += 1
    for source, target in sorted(edges):
        rows.append([timestamp, source, resources[target], "WAITING"])
        timestamp += 1

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "tx_id", "resource_id", "status"])
        writer.writerows(rows)


def run_and_check(executable, nodes, edges):
    write_graph_fixture(nodes, edges)
    expected = expected_from_csv(CSV_PATH)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    try:
        result = subprocess.run(
            [executable], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out while processing a test fixture.")
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    validate_report(expected)


def test_cpp_file_exists():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} is missing."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The analyzer is not a compiled executable."


def test_original_json_output_correctness_and_sorting():
    # This expectation is fixed independently of the mutable CSV path.
    validate_report([["T1", "T2", "T3"], ["T4", "T5"]])
    assert os.path.isfile(CSV_PATH), f"Input CSV file {CSV_PATH} is missing."


def test_source_compiles_and_analyzers_process_fresh_inputs():
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", COMPILED_TEST_EXECUTABLE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "The submitted C++ source did not compile with the required command.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    token = secrets.token_hex(4)
    rng = random.SystemRandom()

    # An acyclic graph.
    dag_nodes = [f"D_{token}_{i}" for i in range(6)]
    dag_edges = {(dag_nodes[i], dag_nodes[j]) for i in range(6) for j in range(i + 1, 6) if rng.random() < 0.45}

    # Self-cycle, two-node cycle, and a separate three-node cycle.
    mixed_nodes = [f"M_{token}_{i}" for i in range(6)]
    mixed_edges = {
        (mixed_nodes[0], mixed_nodes[0]),
        (mixed_nodes[1], mixed_nodes[2]), (mixed_nodes[2], mixed_nodes[1]),
        (mixed_nodes[3], mixed_nodes[4]), (mixed_nodes[4], mixed_nodes[5]),
        (mixed_nodes[5], mixed_nodes[3]),
    }

    # A fresh branching graph with many possible elementary cycles.
    random_nodes = [f"R_{token}_{i}" for i in range(7)]
    random_edges = {(random_nodes[i], random_nodes[(i + 1) % len(random_nodes)]) for i in range(len(random_nodes))}
    for source in random_nodes:
        for target in random_nodes:
            if source != target and rng.random() < 0.30:
                random_edges.add((source, target))

    fixtures = [
        (dag_nodes, dag_edges),
        (mixed_nodes, mixed_edges),
        (random_nodes, random_edges),
    ]

    # Exercise both the required artifact and a fresh compilation of the source.
    for executable in (EXECUTABLE, COMPILED_TEST_EXECUTABLE):
        for nodes, edges in fixtures:
            run_and_check(executable, nodes, edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
