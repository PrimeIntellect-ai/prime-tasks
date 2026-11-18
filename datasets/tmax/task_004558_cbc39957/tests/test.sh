#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import time
from contextlib import contextmanager

import pytest

SOURCE = "/home/user/recovery_processor.c"
EXECUTABLE = "/home/user/recovery_processor"
SUMMARY = "/home/user/recovery_summary.txt"
NODES = "/home/user/graph_backup/nodes.csv"
EDGES = "/home/user/graph_backup/edges.csv"


def read_expected_results(nodes_path=NODES, edges_path=EDGES):
    nodes = {}
    targets = []
    with open(nodes_path, newline="") as f:
        for row in csv.DictReader(f):
            node_id = row["node_id"]
            timestamp = int(row["timestamp"])
            nodes[node_id] = (row["node_type"], timestamp, float(row["value"]))
            if (row["node_type"] == "DATABASE_SERVER" and
                    1600000000 <= timestamp <= 1600086400):
                targets.append(node_id)

    neighbors = {node_id: [] for node_id in targets}
    with open(edges_path, newline="") as f:
        for row in csv.DictReader(f):
            source = row["source_id"]
            if source in neighbors and row["relationship_type"] == "DEPENDS_ON":
                neighbors[source].append(row["target_id"])

    results = {}
    for node_id in targets:
        # Preserve the original verifier's treatment of duplicate target IDs.
        neighbor_ids = set(neighbors[node_id])
        ordered = sorted(
            (nodes[nid] for nid in neighbor_ids if nid in nodes),
            key=lambda item: item[1],
        )
        if not ordered:
            continue
        values = [item[2] for item in ordered]
        window = values[-3:] if len(values) >= 3 else values
        results[node_id] = sum(window) / len(window)
    return results


def read_summary():
    assert os.path.isfile(SUMMARY), f"Output file not found at {SUMMARY}"
    output = {}
    with open(SUMMARY) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 2:
                output[parts[0]] = float(parts[1])
    return output


def assert_results(expected):
    actual = read_summary()
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} results, got {len(actual)}"
    )
    for node_id, expected_value in expected.items():
        assert node_id in actual, f"Missing result for node {node_id}"
        assert abs(actual[node_id] - expected_value) < 1e-2, (
            f"Incorrect moving average for node {node_id}: "
            f"expected {expected_value}, got {actual[node_id]}"
        )


def run_processor(max_runtime=2.0):
    if os.path.exists(SUMMARY):
        os.unlink(SUMMARY)
    start = time.monotonic()
    try:
        proc = subprocess.run(
            [EXECUTABLE], capture_output=True, timeout=max_runtime + 3.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program exceeded the {max_runtime:.1f} second runtime limit")
    runtime = time.monotonic() - start
    assert proc.returncode == 0, (
        f"Program failed with return code {proc.returncode}\n"
        f"Stderr: {proc.stderr.decode(errors='replace')}"
    )
    assert runtime <= max_runtime, (
        f"Runtime was {runtime:.2f} seconds, which exceeds the "
        f"{max_runtime:.1f} seconds threshold."
    )


@contextmanager
def replacement_backup(nodes_text, edges_text):
    with tempfile.TemporaryDirectory() as tmp:
        saved_nodes = os.path.join(tmp, "nodes.csv")
        saved_edges = os.path.join(tmp, "edges.csv")
        shutil.copy2(NODES, saved_nodes)
        shutil.copy2(EDGES, saved_edges)
        try:
            with open(NODES, "w") as f:
                f.write(nodes_text)
            with open(EDGES, "w") as f:
                f.write(edges_text)
            yield
        finally:
            shutil.copy2(saved_nodes, NODES)
            shutil.copy2(saved_edges, EDGES)


@pytest.fixture(scope="session", autouse=True)
def compile_submitted_c_program():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    assert not os.path.islink(SOURCE), "recovery_processor.c must be a submitted source file"
    compile_proc = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", EXECUTABLE, "-lm"],
        capture_output=True,
        text=True,
    )
    assert compile_proc.returncode == 0, (
        "recovery_processor.c did not compile with gcc:\n" + compile_proc.stderr
    )
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled recovery_processor is not an ELF executable"
    yield


def test_recovery_processor_performance_and_correctness():
    # Preserve the original verifier's fixed-backup correctness, execution,
    # output existence, and two-second performance assertions.
    expected = read_expected_results()
    run_processor(2.0)
    assert_results(expected)


def test_processor_parses_changed_csv_and_computes_windows():
    # Values and IDs are chosen only at verification time, so fixed-output
    # scripts cannot satisfy this test.
    rng = random.Random(secrets.randbits(64))
    target_a = rng.randrange(400000, 500000)
    target_b = target_a + 1
    target_empty = target_a + 2
    outside = target_a + 3
    neighbor_ids = [rng.randrange(600000, 900000) for _ in range(7)]
    values = [round(rng.uniform(-80.0, 180.0), 3) for _ in neighbor_ids]

    node_rows = [
        [target_a, "DATABASE_SERVER", 1600000100, 999.0],
        [target_b, "DATABASE_SERVER", 1600086300, 999.0],
        [target_empty, "DATABASE_SERVER", 1600000200, 999.0],
        [outside, "DATABASE_SERVER", 1599999999, 999.0],
    ]
    timestamps = [1600000500, 1600000100, 1600000400, 1600000200,
                  1600000300, 1600000150, 1600000250]
    for nid, ts, value in zip(neighbor_ids, timestamps, values):
        node_rows.append([nid, "OTHER", ts, value])
    rng.shuffle(node_rows)

    edge_rows = [
        [target_a, neighbor_ids[i], "DEPENDS_ON"] for i in range(5)
    ] + [
        [target_b, neighbor_ids[5], "DEPENDS_ON"],
        [target_b, neighbor_ids[6], "DEPENDS_ON"],
        [outside, neighbor_ids[0], "DEPENDS_ON"],
        [target_empty, neighbor_ids[0], "OTHER_REL"],
        [neighbor_ids[0], target_a, "DEPENDS_ON"],
    ]
    rng.shuffle(edge_rows)

    nodes_text = "node_id,node_type,timestamp,value\n" + "".join(
        f"{a},{b},{c},{d}\n" for a, b, c, d in node_rows
    )
    edges_text = "source_id,target_id,relationship_type\n" + "".join(
        f"{a},{b},{c}\n" for a, b, c in edge_rows
    )

    with replacement_backup(nodes_text, edges_text):
        expected = read_expected_results()
        run_processor(2.0)
        assert_results(expected)


def test_indexed_processing_on_large_adversarial_backup():
    # Many targets make repeated full scans quadratic, while an adjacency/hash
    # index handles this backup linearly. The total scale remains comparable to
    # the 100,000-record backup described by the task.
    rng = random.Random(secrets.randbits(64))
    target_count = 15000
    dummy_count = 40000
    base_target = rng.randrange(1000000, 2000000)
    base_neighbor = base_target + 100000
    base_dummy = base_neighbor + target_count * 3 + 100000

    node_lines = ["node_id,node_type,timestamp,value\n"]
    edge_lines = ["source_id,target_id,relationship_type\n"]

    for i in range(target_count):
        target = base_target + i
        node_lines.append(f"{target},DATABASE_SERVER,{1600000000 + (i % 80000)},0\n")
        for j in range(3):
            neighbor = base_neighbor + i * 3 + j
            value = ((i * 17 + j * 11 + rng.randrange(7)) % 1000) / 10.0
            node_lines.append(
                f"{neighbor},OTHER,{1600000100 + j},{value}\n"
            )
            edge_lines.append(f"{target},{neighbor},DEPENDS_ON\n")

    for i in range(dummy_count):
        node_id = base_dummy + i
        node_lines.append(f"{node_id},OTHER,1500000000,10.0\n")
        edge_lines.append(f"{node_id},{node_id + 1},OTHER_REL\n")

    with replacement_backup("".join(node_lines), "".join(edge_lines)):
        expected = read_expected_results()
        run_processor(2.0)
        assert_results(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
