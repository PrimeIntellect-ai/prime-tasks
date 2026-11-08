#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import string
import subprocess
from collections import defaultdict

CSV_PATH = "/home/user/network.csv"
SOURCE_PATH = "/home/user/graph_analyzer.cpp"
EXECUTABLE_PATH = "/home/user/graph_analyzer"
RESULT_PATH = "/home/user/component_result.txt"

with open(CSV_PATH, "rb") as f:
    ORIGINAL_CSV = f.read()


def expected_result(rows):
    transactions = defaultdict(list)
    for row in rows:
        transactions[row["source"]].append({
            "target": row["target"],
            "amount": float(row["amount"]),
            "time_seq": int(row["time_seq"]),
        })

    edges = []
    for source, txs in transactions.items():
        txs.sort(key=lambda x: x["time_seq"])
        cumulative = 0.0
        for tx in txs:
            cumulative += tx["amount"]
            if cumulative > 150.0:
                edges.append((source, tx["target"]))

    adj = defaultdict(set)
    nodes = set()
    for u, v in edges:
        adj[u].add(v)
        adj[v].add(u)
        nodes.add(u)
        nodes.add(v)

    visited = set()
    components = []
    for node in nodes:
        if node in visited:
            continue
        component = []
        stack = [node]
        visited.add(node)
        while stack:
            current = stack.pop()
            component.append(current)
            for neighbor in adj[current]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    stack.append(neighbor)
        components.append(component)

    if not components:
        return 0, ""
    components.sort(key=lambda c: (-len(c), min(c)))
    largest = components[0]
    return len(largest), ",".join(sorted(largest))


def read_rows(path=CSV_PATH):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.DictWriter(
            f, fieldnames=["tx_id", "source", "target", "amount", "time_seq"]
        )
        writer.writeheader()
        writer.writerows(rows)


def run_and_check(rows, label):
    write_rows(rows)
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    completed = subprocess.run(
        [EXECUTABLE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"Program failed on {label} with exit code {completed.returncode}: "
        f"{completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} is missing on {label}."

    with open(RESULT_PATH, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 2, f"Expected exactly 2 lines on {label}, found {len(lines)}."

    expected_size, expected_nodes = expected_result(rows)
    try:
        actual_size = int(lines[0].strip())
    except ValueError as exc:
        raise AssertionError(f"First line is not an integer on {label}: {lines[0]!r}") from exc
    actual_nodes = lines[1].strip()

    assert actual_size == expected_size, (
        f"Expected largest component size {expected_size} on {label}, got {actual_size}."
    )
    assert actual_nodes == expected_nodes, (
        f"Expected nodes {expected_nodes!r} on {label}, got {actual_nodes!r}."
    )


def test_source_code_and_executable_exist():
    assert os.path.isfile(SOURCE_PATH), "Source file /home/user/graph_analyzer.cpp is missing."
    assert os.path.isfile(EXECUTABLE_PATH), "Executable /home/user/graph_analyzer is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "/home/user/graph_analyzer is not executable."

    compiled = subprocess.run(
        ["g++", "-O3", "-std=c++17", "-o", EXECUTABLE_PATH, SOURCE_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compiled.returncode == 0, f"Submitted C++ source failed to compile: {compiled.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH), "Compilation did not create /home/user/graph_analyzer."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "Compiled graph_analyzer is not executable."


def test_component_result_correctness():
    assert os.path.isfile(CSV_PATH), f"Input file {CSV_PATH} is missing."
    rows = read_rows()
    run_and_check(rows, "the original dataset")

    # Preserve the original verifier's nonblank-line and value assertions.
    with open(RESULT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULT_PATH}, found {len(lines)}."
    expected_size, expected_nodes = expected_result(rows)
    assert int(lines[0]) == expected_size
    assert lines[1] == expected_nodes


def test_program_on_fresh_inputs():
    rng = random.Random(secrets.randbits(128))

    def node_name():
        return "N" + "".join(rng.choice(string.ascii_letters) for _ in range(10))

    try:
        # Exercise out-of-order time sequences, the strict threshold, and tie-breaking.
        names = sorted({node_name() for _ in range(12)})
        while len(names) < 12:
            names = sorted(set(names) | {node_name()})
        rows = [
            {"tx_id": 1, "source": names[0], "target": names[2], "amount": "60", "time_seq": 2},
            {"tx_id": 2, "source": names[0], "target": names[1], "amount": "100", "time_seq": 1},
            {"tx_id": 3, "source": names[2], "target": names[3], "amount": "151", "time_seq": 1},
            {"tx_id": 4, "source": names[6], "target": names[7], "amount": "151", "time_seq": 1},
            {"tx_id": 5, "source": names[7], "target": names[8], "amount": "151", "time_seq": 1},
            {"tx_id": 6, "source": names[10], "target": names[11], "amount": "150", "time_seq": 1},
        ]
        rng.shuffle(rows)
        run_and_check(rows, "threshold/order/tie case")

        amounts = ["0", "10", "49.5", "50", "75", "100", "150", "150.0", "151", "200"]
        for case_number in range(6):
            names = list({node_name() for _ in range(18)})
            while len(names) < 18:
                names.append(node_name())
                names = list(set(names))

            rows = []
            tx_id = 1
            for source_index in range(10):
                source = names[source_index]
                count = rng.randint(2, 6)
                times = rng.sample(range(1, 40), count)
                for time_seq in times:
                    target = rng.choice([n for n in names if n != source])
                    rows.append({
                        "tx_id": tx_id,
                        "source": source,
                        "target": target,
                        "amount": rng.choice(amounts),
                        "time_seq": time_seq,
                    })
                    tx_id += 1

            # Guarantee at least one qualifying edge without revealing its randomized names.
            rows.append({
                "tx_id": tx_id,
                "source": names[15],
                "target": names[16],
                "amount": "151",
                "time_seq": 1,
            })
            rng.shuffle(rows)
            run_and_check(rows, f"randomized case {case_number + 1}")
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(ORIGINAL_CSV)
        subprocess.run(
            [EXECUTABLE_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=10, check=False
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
