#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import stat
import subprocess
from collections import defaultdict

SCRIPT_PATH = "/home/user/find_deadlocks.py"
LOCKS_PATH = "/home/user/tx_locks.json"
GRAPH_PATH = "/home/user/resource_graph.nt"
REPORT_PATH = "/home/user/deadlocks_report.csv"


def compute_expected_deadlocks(tx_locks_path=LOCKS_PATH, resource_graph_path=GRAPH_PATH):
    assert os.path.exists(tx_locks_path), f"Missing {tx_locks_path}"
    assert os.path.exists(resource_graph_path), f"Missing {resource_graph_path}"

    with open(tx_locks_path, "r") as f:
        locks = json.load(f)

    granted = defaultdict(list)
    waiting = defaultdict(list)

    for lock in locks:
        tx_id = lock["tx_id"]
        res = lock["resource"]
        state = lock["state"]
        ts = lock["timestamp"]
        if state == "GRANTED":
            granted[res].append((tx_id, ts))
        elif state == "WAITING":
            waiting[tx_id].append((res, ts))

    depends_on = defaultdict(list)
    with open(resource_graph_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = re.match(r'<([^>]+)>\s+<dependsOn>\s+<([^>]+)>\s*\.', line)
            if match:
                depends_on[match.group(1)].append(match.group(2))

    deadlocks = {}
    for tx_a, a_waits in waiting.items():
        for res1, ts_a_wait in a_waits:
            for res2 in depends_on.get(res1, []):
                for tx_b, ts_b_grant in granted.get(res2, []):
                    if tx_a == tx_b:
                        continue
                    for res3, ts_b_wait in waiting.get(tx_b, []):
                        for res4 in depends_on.get(res3, []):
                            for tx_a_check, ts_a_grant in granted.get(res4, []):
                                if tx_a_check == tx_a:
                                    tx_1, tx_2 = sorted([tx_a, tx_b])
                                    min_ts = min(ts_a_wait, ts_b_grant, ts_b_wait, ts_a_grant)
                                    pair = (tx_1, tx_2)
                                    if pair not in deadlocks or min_ts < deadlocks[pair]:
                                        deadlocks[pair] = min_ts

    sorted_deadlocks = sorted(deadlocks.items(), key=lambda x: (x[1], x[0][0]))
    top_5 = sorted_deadlocks[:5]
    return [(k[0], k[1], str(v)) for k, v in top_5]


def assert_report(expected_data):
    assert os.path.exists(REPORT_PATH), f"The output file {REPORT_PATH} was not created."
    with open(REPORT_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"{REPORT_PATH} is empty."

        assert header == ["tx_1", "tx_2", "min_timestamp"], \
            f"CSV header is incorrect. Expected ['tx_1', 'tx_2', 'min_timestamp'], got {header}"
        rows = list(reader)

    assert len(rows) == len(expected_data), \
        f"Expected {len(expected_data)} rows in the report (excluding header), but found {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_data)):
        assert len(actual) == 3, f"Row {i+1} does not have exactly 3 columns: {actual}"
        assert actual[0] == expected[0], f"Row {i+1} tx_1 mismatch: expected {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1} tx_2 mismatch: expected {expected[1]}, got {actual[1]}"
        assert actual[2] == expected[2], f"Row {i+1} min_timestamp mismatch: expected {expected[2]}, got {actual[2]}"


def run_submission():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"{SCRIPT_PATH} failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.exists(REPORT_PATH), f"The output file {REPORT_PATH} was not created by the script."


def write_case(locks, graph):
    with open(LOCKS_PATH, "w") as f:
        json.dump(locks, f, indent=2)
    with open(GRAPH_PATH, "w") as f:
        for edge in graph:
            f.write(edge + "\n")


def test_00_script_exists_and_handles_unseen_inputs():
    assert os.path.lexists(SCRIPT_PATH), f"Missing required script {SCRIPT_PATH}"
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular file"

    with open(LOCKS_PATH, "rb") as f:
        original_locks = f.read()
    with open(GRAPH_PATH, "rb") as f:
        original_graph = f.read()

    token = secrets.token_hex(5)
    rng = random.SystemRandom()

    try:
        locks = []
        graph = []
        bases = [310, 17, 205, 17, 99, 480, 63, 720]
        for i, base in enumerate(bases):
            tx_a = f"TX_{token}_{chr(65 + i)}_z"
            tx_b = f"TX_{token}_{chr(65 + i)}_a"
            grant_a = f"RES_{token}_{i}_GA"
            grant_b = f"RES_{token}_{i}_GB"
            wait_a = f"RES_{token}_{i}_WA"
            wait_b = f"RES_{token}_{i}_WB"
            locks.extend([
                {"tx_id": tx_a, "resource": grant_a, "state": "GRANTED", "timestamp": base + 3},
                {"tx_id": tx_b, "resource": grant_b, "state": "GRANTED", "timestamp": base + 2},
                {"tx_id": tx_a, "resource": wait_a, "state": "WAITING", "timestamp": base},
                {"tx_id": tx_b, "resource": wait_b, "state": "WAITING", "timestamp": base + 7},
            ])
            graph.extend([
                f"<{wait_a}> <dependsOn> <{grant_b}> .",
                f"<{wait_b}> <dependsOn> <{grant_a}> .",
            ])

        noise_a = f"NOISE_{token}_A"
        noise_b = f"NOISE_{token}_B"
        noise_wait = f"NOISE_{token}_WAIT"
        noise_grant = f"NOISE_{token}_GRANT"
        locks.extend([
            {"tx_id": noise_a, "resource": noise_wait, "state": "WAITING", "timestamp": 1},
            {"tx_id": noise_b, "resource": noise_grant, "state": "GRANTED", "timestamp": 2},
        ])
        graph.append(f"<{noise_wait}> <dependsOn> <{noise_grant}> .")
        rng.shuffle(locks)
        rng.shuffle(graph)
        write_case(locks, graph)
        expected = compute_expected_deadlocks()
        run_submission()
        assert_report(expected)

        empty_locks = [
            {"tx_id": f"SINGLE_{token}_A", "resource": f"SINGLE_{token}_W", "state": "WAITING", "timestamp": 8},
            {"tx_id": f"SINGLE_{token}_B", "resource": f"SINGLE_{token}_G", "state": "GRANTED", "timestamp": 4},
        ]
        empty_graph = [f"<SINGLE_{token}_W> <dependsOn> <SINGLE_{token}_G> ."]
        write_case(empty_locks, empty_graph)
        expected = compute_expected_deadlocks()
        run_submission()
        assert_report(expected)
    finally:
        with open(LOCKS_PATH, "wb") as f:
            f.write(original_locks)
        with open(GRAPH_PATH, "wb") as f:
            f.write(original_graph)


def test_deadlocks_report_exists_and_correct():
    run_submission()
    expected_data = compute_expected_deadlocks()
    assert_report(expected_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
