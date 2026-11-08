#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
INPUT_PATH = "/home/user/transactions.csv"
OUTPUT_PATH = "/home/user/top_nodes.json"
SCHEMA_KEYS = {"node", "out_deg", "in_deg", "total_out", "total_in"}

ORIGINAL_CSV = """sender,receiver,amount,timestamp
A,B,50,100
A,C,100,101
B,C,20,102
A,B,5,103
C,A,200,104
D,A,50,105
D,B,15,106
B,D,100,107
C,D,11,108
E,F,10,109
F,E,300,110
"""


def write_csv(text):
    with open(INPUT_PATH, "w") as f:
        f.write(text)


def execute_pipeline():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out.")

    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} was not created by the script."
    )

    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {OUTPUT_PATH} as JSON: {e}")


def assert_schema_and_values(data, expected):
    assert isinstance(data, list), "The top-level JSON structure must be a list."
    assert len(data) == 3, f"Expected exactly 3 nodes in the output, got {len(data)}."

    for i, (actual, expected_item) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Element at index {i} is not a dictionary."
        assert set(actual.keys()) == SCHEMA_KEYS, (
            f"Element at index {i} must contain exactly the schema keys; "
            f"got {sorted(actual.keys())}."
        )
        for key, expected_val in expected_item.items():
            assert key in actual, f"Missing key '{key}' in element at index {i}."
            assert type(actual[key]) is type(expected_val), (
                f"Incorrect type for key '{key}' at index {i}. "
                f"Expected {type(expected_val).__name__}, "
                f"got {type(actual[key]).__name__}."
            )
            assert actual[key] == expected_val, (
                f"Incorrect value for key '{key}' at index {i}. "
                f"Expected {expected_val}, got {actual[key]}."
            )


def derive_expected(rows):
    edges = {}
    nodes = set()
    for sender, receiver, amount, _timestamp in rows:
        if amount <= 10:
            continue
        nodes.add(sender)
        nodes.add(receiver)
        edges[(sender, receiver)] = edges.get((sender, receiver), 0) + amount

    result = []
    for node in nodes:
        outgoing = [(receiver, weight) for (sender, receiver), weight in edges.items()
                    if sender == node]
        incoming = [(sender, weight) for (sender, receiver), weight in edges.items()
                    if receiver == node]
        result.append({
            "node": node,
            "out_deg": len(outgoing),
            "in_deg": len(incoming),
            "total_out": sum(weight for _, weight in outgoing),
            "total_in": sum(weight for _, weight in incoming),
        })

    result.sort(key=lambda item: (-item["total_out"], item["node"]))
    return result[:3]


def rows_to_csv(rows):
    lines = ["sender,receiver,amount,timestamp"]
    lines.extend(f"{s},{r},{a},{t}" for s, r, a, t in rows)
    return "\n".join(lines) + "\n"


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."


def test_pipeline_execution_and_output():
    write_csv(ORIGINAL_CSV)
    data = execute_pipeline()

    expected_data = [
        {
            "node": "F",
            "out_deg": 1,
            "in_deg": 0,
            "total_out": 300,
            "total_in": 0
        },
        {
            "node": "C",
            "out_deg": 2,
            "in_deg": 2,
            "total_out": 211,
            "total_in": 120
        },
        {
            "node": "A",
            "out_deg": 2,
            "in_deg": 2,
            "total_out": 150,
            "total_in": 250
        }
    ]

    assert_schema_and_values(data, expected_data)


def test_pipeline_on_runtime_generated_inputs():
    try:
        for trial in range(3):
            token = secrets.token_hex(5)
            nodes = [f"acct_{token}_{letter}" for letter in "ABCDEFG"]
            rng = random.SystemRandom()
            rows = []
            timestamp = 1000 + trial * 100

            # Ensure every node participates in the filtered graph.
            for i, sender in enumerate(nodes):
                receiver = nodes[(i + 1) % len(nodes)]
                rows.append((sender, receiver, rng.randint(11, 90), timestamp))
                timestamp += 1

            # Add duplicates, reverse edges, threshold cases, and varied weights.
            rows.extend([
                (nodes[0], nodes[1], rng.randint(11, 80), timestamp),
                (nodes[0], nodes[1], rng.randint(11, 80), timestamp + 1),
                (nodes[1], nodes[0], rng.randint(11, 80), timestamp + 2),
                (nodes[2], nodes[5], 10, timestamp + 3),
                (nodes[5], nodes[2], rng.randint(11, 80), timestamp + 4),
                (nodes[3], nodes[6], rng.randint(11, 80), timestamp + 5),
                (nodes[4], nodes[0], rng.randint(11, 80), timestamp + 6),
                (nodes[6], nodes[4], rng.randint(11, 80), timestamp + 7),
                (nodes[2], nodes[3], rng.randint(1, 9), timestamp + 8),
            ])

            for _ in range(20):
                sender, receiver = rng.sample(nodes, 2)
                rows.append((sender, receiver, rng.randint(1, 120), timestamp))
                timestamp += 1

            rng.shuffle(rows)
            expected = derive_expected(rows)
            assert len(expected) == 3
            write_csv(rows_to_csv(rows))
            actual = execute_pipeline()
            assert_schema_and_values(actual, expected)
    finally:
        write_csv(ORIGINAL_CSV)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
