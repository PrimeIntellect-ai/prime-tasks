#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/audit_graph.sh"
REPORT_PATH = "/home/user/compliance_report.txt"
TRANSACTIONS_PATH = "/home/user/transactions.csv"

ORIGINAL_CSV = """tx_id,src_account,dst_account,amount,timestamp
1,ACC_001,ACC_002,500,1620000000
2,ACC_002,ACC_003,300,1620000010
3,ACC_003,ACC_004,100,1620000020
4,ACC_004,ACC_005,100,1620000030
5,ACC_010,ACC_011,900,1620000040
6,ACC_011,ACC_012,900,1620000050
7,ACC_012,ACC_010,900,1620000060
8,ACC_888,ACC_100,500,1620000070
9,ACC_100,ACC_200,500,1620000080
10,ACC_200,ACC_300,500,1620000090
11,ACC_300,ACC_001,500,1620000100
12,ACC_100,ACC_400,200,1620000110
13,ACC_400,ACC_001,200,1620000120
"""


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    try:
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\n"
            f"Stderr: {result.stderr}"
        )
    except Exception as e:
        pytest.fail(f"Failed to execute script: {e}")

    assert os.path.exists(REPORT_PATH), (
        f"Report file {REPORT_PATH} was not created by the script."
    )
    with open(REPORT_PATH, "r") as f:
        return f.read().strip()


def expected_report(rows):
    edges = {(src, dst) for src, dst in rows}
    vertices = {v for edge in edges for v in edge}

    cyclic = set()
    for a in vertices:
        for b in vertices:
            if a == b or (a, b) not in edges:
                continue
            for c in vertices:
                if c == a or c == b:
                    continue
                if (b, c) in edges and (c, a) in edges:
                    cyclic.update((a, b, c))

    adjacency = {}
    for src, dst in edges:
        adjacency.setdefault(src, set()).add(dst)

    queue = deque([("ACC_888", 0)])
    visited = {"ACC_888"}
    distance = None
    while queue:
        node, depth = queue.popleft()
        if node == "ACC_001":
            distance = depth
            break
        for nxt in adjacency.get(node, ()):
            if nxt not in visited:
                visited.add(nxt)
                queue.append((nxt, depth + 1))

    assert distance is not None
    return (
        "CYCLES:\n"
        + ",".join(sorted(cyclic))
        + "\nEXPOSURE_DISTANCE:\n"
        + str(distance)
    )


def write_transactions(rows):
    with open(TRANSACTIONS_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["tx_id", "src_account", "dst_account", "amount", "timestamp"])
        for tx_id, (src, dst) in enumerate(rows, 1):
            writer.writerow([tx_id, src, dst, 100 + tx_id, 1700000000 + tx_id])


def random_accounts(count):
    result = []
    used = {"ACC_001", "ACC_888"}
    while len(result) < count:
        account = "ACC_" + secrets.token_hex(5).upper()
        if account not in used:
            used.add(account)
            result.append(account)
    return result


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    with open(TRANSACTIONS_PATH, "w") as f:
        f.write(ORIGINAL_CSV)

    content = run_script()
    expected_content = (
        "CYCLES:\n"
        "ACC_010,ACC_011,ACC_012\n"
        "EXPOSURE_DISTANCE:\n"
        "3"
    )
    assert content == expected_content, (
        f"Report content does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )


def test_graph_analysis_on_unseen_inputs():
    nodes = random_accounts(12)
    cases = [
        [
            (nodes[0], nodes[1]), (nodes[1], nodes[2]), (nodes[2], nodes[0]),
            ("ACC_888", nodes[3]), (nodes[3], nodes[4]),
            (nodes[4], nodes[5]), (nodes[5], "ACC_001"),
            ("ACC_888", nodes[10]), (nodes[10], nodes[11]),
            (nodes[6], nodes[7]), (nodes[7], nodes[8]),
        ],
        [
            (nodes[0], nodes[1]), (nodes[1], nodes[2]), (nodes[2], nodes[0]),
            (nodes[2], nodes[3]), (nodes[3], nodes[4]), (nodes[4], nodes[2]),
            (nodes[0], nodes[1]),
            ("ACC_888", nodes[6]), (nodes[6], "ACC_001"),
            (nodes[7], nodes[8]), (nodes[9], nodes[10]),
        ],
        [
            (nodes[0], nodes[1]), (nodes[1], nodes[2]), (nodes[2], nodes[0]),
            (nodes[5], nodes[6]), (nodes[6], nodes[7]), (nodes[7], nodes[5]),
            ("ACC_888", nodes[3]), (nodes[3], nodes[4]),
            (nodes[4], nodes[8]), (nodes[8], nodes[9]),
            (nodes[9], "ACC_001"),
            ("ACC_001", nodes[10]), (nodes[11], "ACC_888"),
        ],
    ]

    try:
        for rows in cases:
            write_transactions(rows)
            expected = expected_report(rows)
            content = run_script()
            assert content == expected, (
                "Report content is incorrect for an unseen transaction graph.\n"
                f"Expected:\n{expected}\nGot:\n{content}"
            )
    finally:
        with open(TRANSACTIONS_PATH, "w") as f:
            f.write(ORIGINAL_CSV)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
