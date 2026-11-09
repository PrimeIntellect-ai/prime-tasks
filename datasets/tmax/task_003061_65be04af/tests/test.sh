#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile
from collections import defaultdict

import pytest

ENTRY_POINT = "/home/user/validate_batch"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_validator(batch_dir: str) -> str:
    """Run the user's validation script and return its stripped output."""
    try:
        result = subprocess.run(
            [ENTRY_POINT, batch_dir],
            capture_output=True,
            text=True,
            timeout=15
        )
        return result.stdout.strip()
    except Exception as e:
        return f"ERROR: {str(e)}"


def test_entry_point_exists_and_executable():
    assert os.path.isfile(ENTRY_POINT), f"Entry point {ENTRY_POINT} does not exist."
    assert os.access(ENTRY_POINT, os.X_OK), f"Entry point {ENTRY_POINT} is not executable."


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."
    batches = [os.path.join(CLEAN_CORPUS_DIR, d) for d in os.listdir(CLEAN_CORPUS_DIR) if os.path.isdir(os.path.join(CLEAN_CORPUS_DIR, d))]
    assert len(batches) > 0, "No batches found in clean corpus."

    failures = []
    for batch in batches:
        output = run_validator(batch)
        if output != "ACCEPT":
            failures.append(f"{os.path.basename(batch)} (Output: {output})")

    assert not failures, f"{len(failures)} of {len(batches)} clean batches modified/rejected. Offending batches: {', '.join(failures)}"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    batches = [os.path.join(EVIL_CORPUS_DIR, d) for d in os.listdir(EVIL_CORPUS_DIR) if os.path.isdir(os.path.join(EVIL_CORPUS_DIR, d))]
    assert len(batches) > 0, "No batches found in evil corpus."

    failures = []
    for batch in batches:
        output = run_validator(batch)
        if output != "REJECT":
            failures.append(f"{os.path.basename(batch)} (Output: {output})")

    assert not failures, f"{len(failures)} of {len(batches)} evil batches bypassed/accepted. Offending batches: {', '.join(failures)}"


def expected_for_batch(batch_dir: str) -> str:
    """Independently derive the result from the generated CSV files."""
    with open(os.path.join(batch_dir, "nodes.csv"), newline="") as f:
        nodes = list(csv.DictReader(f))
    with open(os.path.join(batch_dir, "edges.csv"), newline="") as f:
        edges = list(csv.DictReader(f))

    graph = defaultdict(list)
    vertices = {row["id"] for row in nodes}
    for edge in edges:
        parent = edge["parent_id"]
        child = edge["child_id"]
        vertices.add(parent)
        vertices.add(child)
        graph[parent].append(child)

    state = {}

    def has_cycle(vertex):
        if state.get(vertex) == 1:
            return True
        if state.get(vertex) == 2:
            return False
        state[vertex] = 1
        for child in graph[vertex]:
            if has_cycle(child):
                return True
        state[vertex] = 2
        return False

    if any(has_cycle(vertex) for vertex in vertices if state.get(vertex, 0) == 0):
        return "REJECT"

    departments = defaultdict(list)
    for row in nodes:
        departments[row["department"]].append(row)
    for department_nodes in departments.values():
        ordered = sorted(department_nodes, key=lambda row: row["timestamp"])
        costs = [int(row["cost"]) for row in ordered]
        for index in range(len(costs) - 2):
            if sum(costs[index:index + 3]) >= 50000:
                return "REJECT"
    return "ACCEPT"


def write_generated_batch(batch_dir: str, mode: str, rng):
    os.makedirs(batch_dir)
    count = rng.randint(6, 10)
    ids = [str(value) for value in rng.sample(range(10000, 99999), count)]
    departments = ["Ops", "Legal", "Sales"]
    nodes = []

    if mode in ("equal_limit", "over_limit"):
        target_costs = [17000, 17000, 16000 if mode == "equal_limit" else 16001]
        for index in range(3):
            nodes.append({
                "id": ids[index],
                "department": "Special",
                "timestamp": f"2024-01-{index + 1:02d}",
                "cost": str(target_costs[index]),
            })
        for index in range(3, count):
            nodes.append({
                "id": ids[index],
                "department": rng.choice(departments),
                "timestamp": f"2024-02-{index + 1:02d}",
                "cost": str(rng.randint(100, 12000)),
            })
    else:
        for index in range(count):
            nodes.append({
                "id": ids[index],
                "department": rng.choice(departments),
                "timestamp": f"2024-03-{index + 1:02d}",
                "cost": str(rng.randint(100, 14000)),
            })

    # The initial ID order is a topological order, so these edges form a DAG.
    edges = [{"parent_id": ids[index], "child_id": ids[index + 1]} for index in range(count - 1)]
    for parent_index in range(count):
        for child_index in range(parent_index + 2, count):
            if rng.random() < 0.18:
                edges.append({"parent_id": ids[parent_index], "child_id": ids[child_index]})
    if mode == "cycle":
        edges.append({"parent_id": ids[2], "child_id": ids[0]})

    # Prevent implementations from relying on CSV row order instead of timestamps.
    rng.shuffle(nodes)
    rng.shuffle(edges)

    with open(os.path.join(batch_dir, "nodes.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "department", "timestamp", "cost"])
        writer.writeheader()
        writer.writerows(nodes)
    with open(os.path.join(batch_dir, "edges.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["parent_id", "child_id"])
        writer.writeheader()
        writer.writerows(edges)


def test_generated_hidden_batches():
    rng = random.SystemRandom()
    failures = []
    expected_outputs = []
    modes = ["clean", "cycle", "equal_limit", "over_limit"] * 3
    rng.shuffle(modes)

    with tempfile.TemporaryDirectory(prefix="batch_validation_") as root:
        for index, mode in enumerate(modes):
            batch_name = f"case_{secrets.token_hex(8)}_{index}"
            batch_dir = os.path.join(root, batch_name)
            write_generated_batch(batch_dir, mode, rng)
            expected = expected_for_batch(batch_dir)
            expected_outputs.append(expected)
            actual = run_validator(batch_dir)
            if actual != expected:
                failures.append(f"{batch_name}: expected {expected}, got {actual}")

    assert "ACCEPT" in expected_outputs and "REJECT" in expected_outputs
    assert not failures, "Generated batch failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
