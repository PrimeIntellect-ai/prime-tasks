#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest


def test_video_analysis_output():
    analysis_file = "/home/user/video_analysis.json"
    assert os.path.exists(analysis_file), f"File {analysis_file} does not exist."

    with open(analysis_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{analysis_file} is not valid JSON.")

    assert "frame_number" in data, "Missing 'frame_number' in video_analysis.json"
    assert "transaction_id" in data, "Missing 'transaction_id' in video_analysis.json"
    assert data["frame_number"] == 142, f"Expected frame_number 142, got {data['frame_number']}"
    assert data["transaction_id"] == "TX_8432", f"Expected transaction_id 'TX_8432', got '{data['transaction_id']}'"


def run_detector(script_path, file_path, expected, label):
    try:
        result = subprocess.run(
            ["python3", script_path, file_path],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {label}")

    assert result.returncode == 0, f"Detector crashed on {label}: {result.stderr}"
    try:
        out_data = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Detector produced invalid JSON on {label}: {result.stdout!r}")

    assert out_data == {"status": expected}, (
        f"Detector returned {out_data!r} on {label}; expected exactly "
        f"{{'status': {expected!r}}}"
    )


def test_deadlock_detector_script():
    script_path = "/home/user/deadlock_detector.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a file."

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_failures = []
    clean_failures = []

    for file_path in evil_files:
        result = subprocess.run(
            ["python3", script_path, file_path],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            evil_failures.append(f"{os.path.basename(file_path)} (crashed)")
            continue
        try:
            out_data = json.loads(result.stdout.strip())
            if out_data.get("status") != "deadlock":
                evil_failures.append(f"{os.path.basename(file_path)} (got {out_data.get('status')})")
        except json.JSONDecodeError:
            evil_failures.append(f"{os.path.basename(file_path)} (invalid JSON output)")

    for file_path in clean_files:
        result = subprocess.run(
            ["python3", script_path, file_path],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            clean_failures.append(f"{os.path.basename(file_path)} (crashed)")
            continue
        try:
            out_data = json.loads(result.stdout.strip())
            if out_data.get("status") != "clean":
                clean_failures.append(f"{os.path.basename(file_path)} (got {out_data.get('status')})")
        except json.JSONDecodeError:
            clean_failures.append(f"{os.path.basename(file_path)} (invalid JSON output)")

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def oracle_status(snapshot):
    transactions = snapshot.get("active_transactions", [])
    holders = {}
    for tx in transactions:
        for resource in tx.get("holds_locks_on", []):
            holders.setdefault(resource, []).append(tx["tx_id"])

    graph = {tx["tx_id"]: set() for tx in transactions}
    for tx in transactions:
        for resource in tx.get("waiting_for_locks_on", []):
            graph[tx["tx_id"]].update(holders.get(resource, []))

    state = {}

    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for neighbor in graph.get(node, ()):
            if visit(neighbor):
                return True
        state[node] = 2
        return False

    return "deadlock" if any(visit(node) for node in graph if state.get(node) != 2) else "clean"


def graph_snapshot(edges, rng):
    count = len(edges)
    tx_ids = ["TX_" + secrets.token_hex(6) for _ in range(count)]
    primary = ["RES_" + secrets.token_hex(7) for _ in range(count)]
    extra = ["AUX_" + secrets.token_hex(7) for _ in range(count)]
    transactions = []

    for index in range(count):
        held = [primary[index]]
        if rng.random() < 0.45:
            held.append(extra[index])
        waiting = []
        for target in edges[index]:
            target_resources = [primary[target]]
            if rng.random() < 0.35:
                target_resources.append(extra[target])
            waiting.append(rng.choice(target_resources))
        if rng.random() < 0.25:
            waiting.append("UNHELD_" + secrets.token_hex(7))
        transactions.append({
            "tx_id": tx_ids[index],
            "holds_locks_on": held,
            "waiting_for_locks_on": waiting,
        })

    rng.shuffle(transactions)
    return {"active_transactions": transactions}


def test_detector_on_hidden_adversarial_inputs():
    script_path = "/home/user/deadlock_detector.py"
    assert os.path.isfile(script_path), f"Script {script_path} is not a file."

    rng = random.SystemRandom()
    snapshots = [
        {"active_transactions": []},
        graph_snapshot([set()], rng),
        graph_snapshot([{0}], rng),
        graph_snapshot([{1}, {0}], rng),
        graph_snapshot([{1}, {2}, set()], rng),
        graph_snapshot([{1}, {2}, {3}, {1}], rng),
        graph_snapshot([{1, 2}, {3}, {3}, set()], rng),
    ]

    # Deep acyclic and cyclic chains exercise transitive waits beyond the fixed fixtures.
    depth = 220
    clean_chain = [{i + 1} if i + 1 < depth else set() for i in range(depth)]
    cyclic_chain = [{i + 1} if i + 1 < depth else {0} for i in range(depth)]
    snapshots.append(graph_snapshot(clean_chain, rng))
    snapshots.append(graph_snapshot(cyclic_chain, rng))

    # Random graph cases have unpredictable identifiers, resources, order, paths, and answers.
    for _ in range(32):
        size = rng.randint(2, 24)
        probability = rng.uniform(0.03, 0.22)
        edges = []
        for source in range(size):
            edges.append({target for target in range(size) if rng.random() < probability})
        snapshots.append(graph_snapshot(edges, rng))

    # Shared lock ownership: waiting on a resource creates edges to every holder.
    shared_resource = "SHARED_" + secrets.token_hex(8)
    other_resource = "OTHER_" + secrets.token_hex(8)
    snapshots.append({"active_transactions": [
        {"tx_id": "A_" + secrets.token_hex(4), "holds_locks_on": [shared_resource], "waiting_for_locks_on": []},
        {"tx_id": "B_" + secrets.token_hex(4), "holds_locks_on": [shared_resource], "waiting_for_locks_on": [other_resource]},
        {"tx_id": "C_" + secrets.token_hex(4), "holds_locks_on": [other_resource], "waiting_for_locks_on": []},
    ]})

    rng.shuffle(snapshots)
    temp_dir = tempfile.mkdtemp(prefix="lock_snapshots_" + secrets.token_hex(5) + "_")
    seen = set()
    try:
        for snapshot in snapshots:
            expected = oracle_status(snapshot)
            seen.add(expected)
            file_path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(file_path, "w") as handle:
                json.dump(snapshot, handle)
            run_detector(script_path, file_path, expected, os.path.basename(file_path))
    finally:
        for file_path in glob.glob(os.path.join(temp_dir, "*")):
            os.unlink(file_path)
        os.rmdir(temp_dir)

    assert seen == {"clean", "deadlock"}, "Generated suite did not cover both classifications."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
