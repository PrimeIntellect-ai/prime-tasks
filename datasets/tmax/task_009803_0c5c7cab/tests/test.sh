#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from collections import defaultdict

SCRIPT_PATH = "/home/user/find_deadlocks.sh"
REPORT_PATH = "/home/user/deadlocks_report.csv"
LOCKS_PATH = "/home/user/data/locks.csv"
HEADER = "tx_1,tx_2,resource_1,resource_2"

ORIGINAL_LOCKS = """tx_id,resource_id,status,timestamp
T1,R1,GRANTED,1
T2,R2,GRANTED,2
T1,R2,WAITING,3
T2,R1,WAITING,4
T3,R3,GRANTED,5
T4,R4,GRANTED,6
T3,R4,WAITING,7
T4,R3,WAITING,8
T5,R5,GRANTED,9
T6,R6,GRANTED,10
T5,R6,WAITING,11
T7,R7,GRANTED,12
T8,R8,GRANTED,13
T8,R7,WAITING,14
T7,R8,WAITING,15
T9,R9,GRANTED,16
T10,R10,GRANTED,17
T9,R10,WAITING,18
T11,R11,GRANTED,19
T10,R11,WAITING,20
"""


def write_locks(records):
    with open(LOCKS_PATH, "w") as f:
        f.write("tx_id,resource_id,status,timestamp\n")
        for tx, resource, status, timestamp in records:
            f.write(f"{tx},{resource},{status},{timestamp}\n")


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["bash", SCRIPT_PATH], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Script failed to execute. stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"Report file {REPORT_PATH} was not created by the script."
    )
    with open(REPORT_PATH, "r") as f:
        return f.read().strip()


def expected_report(records):
    granted = defaultdict(set)
    waiting = defaultdict(list)
    for tx, resource, status, _ in records:
        if status == "GRANTED":
            granted[resource].add(tx)
        elif status == "WAITING":
            waiting[tx].append(resource)

    rows = set()
    for tx_a, resources_a in waiting.items():
        for resource_a in resources_a:
            for tx_b in granted[resource_a]:
                if tx_a == tx_b:
                    continue
                for resource_b in waiting.get(tx_b, []):
                    if tx_a in granted[resource_b]:
                        if tx_a < tx_b:
                            rows.add((tx_a, tx_b, resource_a, resource_b))
                        else:
                            rows.add((tx_b, tx_a, resource_b, resource_a))

    ordered = sorted(rows, key=lambda row: (row[0], row[1]))
    return "\n".join([HEADER] + [",".join(row) for row in ordered])


def make_random_case():
    rng = random.SystemRandom()
    tag = secrets.token_hex(5)
    txs = [f"T{rng.randrange(1, 500)}_{tag}_{i}" for i in range(12)]
    rng.shuffle(txs)
    resources = [f"R{rng.randrange(1, 500)}_{tag}_{i}" for i in range(12)]
    rng.shuffle(resources)

    records = []
    timestamp = 1
    owned_resource = {}
    for tx, resource in zip(txs, resources):
        owned_resource[tx] = resource
        records.append((tx, resource, "GRANTED", timestamp))
        timestamp += 1

    pair_count = rng.choice([2, 3])
    used = 0
    for _ in range(pair_count):
        tx_a, tx_b = txs[used], txs[used + 1]
        records.append((tx_a, owned_resource[tx_b], "WAITING", timestamp))
        timestamp += 1
        records.append((tx_b, owned_resource[tx_a], "WAITING", timestamp))
        timestamp += 1
        used += 2

    # All remaining transactions form a cycle longer than two, so they are
    # blocked but do not constitute any size-2 deadlock.
    remaining = txs[used:]
    for index, tx in enumerate(remaining):
        target = remaining[(index + 1) % len(remaining)]
        records.append((tx, owned_resource[target], "WAITING", timestamp))
        timestamp += 1

    # Include a wait for a resource with no holder.
    records.append((txs[-1], f"UNGRANTED_{tag}", "WAITING", timestamp))

    # Physical row order must not determine the result; timestamps still put
    # all grants before waits.
    rng.shuffle(records)
    return records


def test_find_deadlocks_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_script_execution_and_output():
    with open(LOCKS_PATH, "w") as f:
        f.write(ORIGINAL_LOCKS)

    expected_content = """tx_1,tx_2,resource_1,resource_2
T1,T2,R2,R1
T3,T4,R4,R3
T7,T8,R8,R7"""
    content = run_script()
    assert content == expected_content, (
        f"Content of {REPORT_PATH} is incorrect. Got:\n{content}"
    )


def test_script_processes_changed_inputs():
    try:
        for _ in range(4):
            records = make_random_case()
            write_locks(records)
            expected = expected_report(records)
            content = run_script()
            assert content == expected, (
                "Report is incorrect for a changed locks.csv input. "
                f"Expected:\n{expected}\nGot:\n{content}"
            )
    finally:
        with open(LOCKS_PATH, "w") as f:
            f.write(ORIGINAL_LOCKS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
