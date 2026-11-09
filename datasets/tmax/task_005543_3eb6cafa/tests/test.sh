#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import uuid

RS_PATH = "/home/user/detector.rs"
LOCKS_PATH = "/home/user/locks.csv"
OUTPUT_PATH = "/home/user/deadlock.txt"
BINARY_PATH = "/tmp/detector_submission"


def test_rust_file_exists():
    assert os.path.isfile(RS_PATH), f"Expected Rust source file {RS_PATH} does not exist."


def test_deadlock_txt_correct():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "200,201,202,203,204,205"
    assert content == expected_content, f"Content of {OUTPUT_PATH} is incorrect. Expected '{expected_content}', got '{content}'."


def derive_cycle(rows):
    holders = {}
    nodes = set()
    for row in rows:
        tx = int(row["tx_id"])
        nodes.add(tx)
        if row["state"] == "HOLDING":
            holders.setdefault(row["resource"], []).append(tx)

    graph = {tx: set() for tx in nodes}
    for row in rows:
        if row["state"] == "WAITING":
            waiter = int(row["tx_id"])
            graph[waiter].update(holders.get(row["resource"], []))

    def reaches(start, target):
        stack = [start]
        seen = set()
        while stack:
            node = stack.pop()
            if node == target:
                return True
            if node not in seen:
                seen.add(node)
                stack.extend(graph.get(node, ()))
        return False

    cycle_nodes = []
    for node in nodes:
        if any(reaches(neighbor, node) for neighbor in graph[node]):
            cycle_nodes.append(node)
    return sorted(cycle_nodes)


def write_fixture(cycle_length, tail_length):
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 900000), cycle_length + tail_length + 1)
    cycle = ids[:cycle_length]
    tails = ids[cycle_length:cycle_length + tail_length]
    all_nodes = ids
    resources = {tx: "res_" + uuid.uuid4().hex for tx in all_nodes}

    rows = []
    for tx in all_nodes:
        rows.append({"tx_id": str(tx), "resource": resources[tx], "state": "HOLDING"})

    for index, waiter in enumerate(cycle):
        holder = cycle[(index + 1) % len(cycle)]
        rows.append({"tx_id": str(waiter), "resource": resources[holder], "state": "WAITING"})

    previous = cycle[0]
    for waiter in tails:
        rows.append({"tx_id": str(waiter), "resource": resources[previous], "state": "WAITING"})
        previous = waiter

    rng.shuffle(rows)
    with open(LOCKS_PATH, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["tx_id", "resource", "state"])
        writer.writeheader()
        writer.writerows(rows)
    return rows


def run_and_check(rows):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run([BINARY_PATH], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Detector exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), "Detector did not create /home/user/deadlock.txt"
    with open(OUTPUT_PATH, "r") as f:
        actual = f.read().strip()
    expected = ",".join(str(tx) for tx in derive_cycle(rows))
    assert actual == expected, f"Expected dynamically derived cycle '{expected}', got '{actual}'"


def test_rust_program_compiles_and_detects_cycles():
    compile_result = subprocess.run(
        ["rustc", RS_PATH, "-o", BINARY_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Rust source failed to compile: {compile_result.stderr}"

    with open(LOCKS_PATH, "r") as f:
        original_locks = f.read()

    try:
        with open(LOCKS_PATH, newline="") as f:
            original_rows = list(csv.DictReader(f))
        run_and_check(original_rows)
        run_and_check(write_fixture(cycle_length=3, tail_length=3))
        run_and_check(write_fixture(cycle_length=6, tail_length=4))
    finally:
        with open(LOCKS_PATH, "w") as f:
            f.write(original_locks)
        subprocess.run([BINARY_PATH], capture_output=True, text=True, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
