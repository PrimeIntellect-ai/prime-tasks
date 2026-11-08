#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import time
import subprocess
import pytest
from collections import Counter, defaultdict

CSV_PATH = "/home/user/edges.csv"
EXE_PATH = "/home/user/query_engine_opt"


def read_edges(path):
    with open(path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) > 0 and lines != [""], f"{path} is empty."

    edges = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Line '{line}' in {path} does not have exactly two comma-separated values."
        try:
            edges.append((int(parts[0].strip()), int(parts[1].strip())))
        except ValueError:
            pytest.fail(f"Line '{line}' in {path} contains non-integer node IDs.")
    return edges


def normalize(text):
    return "\n".join(
        line.replace(" ", "")
        for line in text.strip().split("\n")
        if line.strip()
    )


def compute_expected_output(edges):
    adj = defaultdict(list)
    for u, v in edges:
        adj[u].append(v)

    # MATCH creates a group only for a nodes that participate in at least one
    # complete length-2 path. Nodes with a zero count must not produce rows.
    path_counts = {}
    for a, destinations in adj.items():
        count = sum(len(adj[b]) for b in destinations)
        if count > 0:
            path_counts[a] = count

    output_lines = []
    rolling_window = []
    for a in sorted(path_counts):
        rolling_window.append(path_counts[a])
        if len(rolling_window) > 3:
            rolling_window.pop(0)
        output_lines.append(f"{a},{sum(rolling_window)}")

    return "\n".join(output_lines)


def run_engine(expected_output):
    result = subprocess.run(
        [EXE_PATH], cwd="/home/user", capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"Executable failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert normalize(result.stdout) == normalize(expected_output), (
        "The output of the optimized engine does not match the expected "
        "mathematical result."
    )


def test_edges_csv_exists_format_and_recovery():
    assert os.path.exists(CSV_PATH), f"{CSV_PATH} does not exist."
    recovered_edges = read_edges(CSV_PATH)

    rng = random.Random(42)
    recorded_edges = [
        (rng.randint(1, 100), rng.randint(1, 100)) for _ in range(250)
    ]
    assert Counter(recovered_edges) == Counter(recorded_edges), (
        "edges.csv does not contain exactly the edge insertions recorded in "
        "transaction_monitor.mp4."
    )


def test_optimization_report_exists():
    report_path = "/home/user/optimization_report.txt"
    assert os.path.exists(report_path), f"Optimization report missing at {report_path}."
    assert os.path.getsize(report_path) > 0, f"Optimization report at {report_path} is empty."


def test_query_engine_on_recovered_graph():
    assert os.path.exists(EXE_PATH), f"Optimized executable missing at {EXE_PATH}."
    assert os.access(EXE_PATH, os.X_OK), f"File at {EXE_PATH} is not executable."

    recovered_edges = read_edges(CSV_PATH)
    run_engine(compute_expected_output(recovered_edges))


def test_query_engine_performance_and_correctness():
    assert os.path.exists(EXE_PATH), f"Optimized executable missing at {EXE_PATH}."
    assert os.access(EXE_PATH, os.X_OK), f"File at {EXE_PATH} is not executable."

    num_edges = 100000
    edges = []
    for i in range(1, num_edges + 1):
        edges.append((i, i + 1))
        if i % 10 == 0:
            edges.append((i, i + 2))

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        with open(CSV_PATH, "w") as f:
            for u, v in edges:
                f.write(f"{u},{v}\n")

        expected_output = compute_expected_output(edges)

        start_time = time.time()
        result = subprocess.run(
            [EXE_PATH], cwd="/home/user", capture_output=True, text=True
        )
        execution_time = time.time() - start_time

        assert result.returncode == 0, (
            f"Executable failed with return code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
        assert normalize(result.stdout) == normalize(expected_output), (
            "The output of the optimized engine does not match the expected "
            "mathematical result."
        )

        threshold = 0.15
        assert execution_time <= threshold, (
            f"Execution time {execution_time:.4f}s exceeded the threshold of "
            f"{threshold}s."
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
