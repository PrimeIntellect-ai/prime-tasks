#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import glob
import random
import secrets
import subprocess
import tempfile
import pytest


def detector_command():
    script_py = "/home/user/detect_deadlocks.py"
    script_sh = "/home/user/detect_deadlocks.sh"

    if os.path.isfile(script_py):
        return ["python3", script_py]
    if os.path.isfile(script_sh):
        return ["bash", script_sh]
    pytest.fail("Could not find detect_deadlocks.py or detect_deadlocks.sh in /home/user/")


def test_video_graph_json():
    json_path = "/home/user/video_graph.json"
    assert os.path.isfile(json_path), f"Missing {json_path}"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file.")

    assert "edges" in data, "JSON must contain 'edges' key"
    edges = data["edges"]

    expected_edges = [
        {"from": "T100", "to": "R50", "type": "HOLDS"},
        {"from": "T101", "to": "R51", "type": "HOLDS"},
        {"from": "T100", "to": "R51", "type": "WAITS_FOR"},
        {"from": "T102", "to": "R52", "type": "HOLDS"},
        {"from": "T100", "to": "R51", "type": "WAITS_FOR"},
        {"from": "T102", "to": "R52", "type": "HOLDS"},
        {"from": "T101", "to": "R50", "type": "WAITS_FOR"}
    ]

    # Preserve the original expected graph (the two duplicate entries above are
    # removed before comparison so the asserted edge set remains unchanged).
    expected_edges = [
        {"from": "T100", "to": "R50", "type": "HOLDS"},
        {"from": "T101", "to": "R51", "type": "HOLDS"},
        {"from": "T100", "to": "R51", "type": "WAITS_FOR"},
        {"from": "T102", "to": "R52", "type": "HOLDS"},
        {"from": "T101", "to": "R50", "type": "WAITS_FOR"}
    ]

    assert len(edges) == len(expected_edges), f"Expected {len(expected_edges)} edges, got {len(edges)}"

    for expected in expected_edges:
        assert expected in edges, f"Missing expected edge: {expected}"


def test_adversarial_corpus():
    cmd_base = detector_command()

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        res = subprocess.run(cmd_base + [evil_file], capture_output=True, text=True)
        out = res.stdout.strip()
        if out != "DEADLOCK":
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        res = subprocess.run(cmd_base + [clean_file], capture_output=True, text=True)
        out = res.stdout.strip()
        if out != "SAFE":
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {clean_modified}")

    if errors:
        pytest.fail(" | ".join(errors))


def graph_has_deadlock(edges):
    holders = {}
    transactions = set()
    for edge in edges:
        transactions.add(edge["from"])
        if edge["type"] == "HOLDS":
            holders.setdefault(edge["to"], set()).add(edge["from"])

    dependencies = {transaction: set() for transaction in transactions}
    for edge in edges:
        if edge["type"] == "WAITS_FOR":
            for holder in holders.get(edge["to"], set()):
                dependencies.setdefault(edge["from"], set()).add(holder)
                dependencies.setdefault(holder, set())

    state = {}

    def visit(transaction):
        if state.get(transaction) == 1:
            return True
        if state.get(transaction) == 2:
            return False
        state[transaction] = 1
        for dependency in dependencies.get(transaction, ()):
            if visit(dependency):
                return True
        state[transaction] = 2
        return False

    return any(visit(transaction) for transaction in dependencies if state.get(transaction, 0) == 0)


def make_generated_case(rng, deadlocking):
    count = rng.randint(4, 10)
    transactions = ["X_" + secrets.token_hex(6) for _ in range(count)]
    dependencies = set()

    # Add an acyclic background graph using a hidden random topological order.
    order = transactions[:]
    rng.shuffle(order)
    for i in range(count):
        for j in range(i + 1, count):
            if rng.random() < 0.20:
                dependencies.add((order[i], order[j]))

    if deadlocking:
        cycle = rng.sample(transactions, rng.randint(2, min(6, count)))
        for i, transaction in enumerate(cycle):
            dependencies.add((transaction, cycle[(i + 1) % len(cycle)]))

    edges = []
    for waiter, holder in dependencies:
        resource = "Q_" + secrets.token_hex(7)
        edges.append({"from": holder, "to": resource, "type": "HOLDS"})
        edges.append({"from": waiter, "to": resource, "type": "WAITS_FOR"})

    # Include irrelevant held resources and waits on currently unheld resources.
    for _ in range(rng.randint(1, 4)):
        edges.append({
            "from": rng.choice(transactions),
            "to": "Q_" + secrets.token_hex(7),
            "type": "HOLDS"
        })
    for _ in range(rng.randint(1, 3)):
        edges.append({
            "from": rng.choice(transactions),
            "to": "Q_" + secrets.token_hex(7),
            "type": "WAITS_FOR"
        })

    rng.shuffle(edges)
    assert graph_has_deadlock(edges) == deadlocking
    return {"edges": edges}


def test_generated_unlabelled_graphs():
    cmd_base = detector_command()
    rng = random.SystemRandom()
    cases = []
    for _ in range(16):
        cases.append(make_generated_case(rng, False))
        cases.append(make_generated_case(rng, True))
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="graphcheck_") as temp_dir:
        for graph in cases:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w") as graph_file:
                json.dump(graph, graph_file)

            expected = "DEADLOCK" if graph_has_deadlock(graph["edges"]) else "SAFE"
            try:
                result = subprocess.run(
                    cmd_base + [path], capture_output=True, text=True, timeout=5
                )
            except subprocess.TimeoutExpired:
                pytest.fail("Deadlock detector timed out on a generated graph")

            assert result.returncode == 0, (
                f"Detector exited with status {result.returncode} on a generated graph: "
                f"{result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"Generated graph expected {expected}, got {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
