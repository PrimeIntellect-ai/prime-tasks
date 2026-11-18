#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from collections import defaultdict

import pytest

INPUT_FILE = "/home/user/transactions.csv"
OUTPUT_FILE = "/home/user/node_metrics.csv"
SOURCE_FILE = "/home/user/graph_etl.cpp"
EXECUTABLE_FILE = "/home/user/graph_etl"

ORIGINAL_INPUT = b"""source,target,amount,timestamp
A,B,100,1
A,B,150,2
C,B,200,3
D,B,50,4
E,B,300,5
F,B,10,6
B,C,500,7
A,C,400,8
C,A,50,9
C,A,60,10
E,F,100,11
"""


def test_input_is_original():
    """Ensure the writable input was not replaced to make the expected graph empty."""
    assert os.path.isfile(INPUT_FILE), f"Input file {INPUT_FILE} is missing."
    with open(INPUT_FILE, "rb") as f:
        assert f.read() == ORIGINAL_INPUT, "transactions.csv was modified from the provided input."


def test_node_metrics_exists():
    """Verify that the output file node_metrics.csv has been created."""
    assert os.path.isfile(OUTPUT_FILE), "The output file /home/user/node_metrics.csv does not exist."


def test_node_metrics_contents():
    """Verify that the node_metrics.csv contains the correct windowed top-K sum aggregation."""
    input_file = INPUT_FILE
    output_file = OUTPUT_FILE

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    # 1. Compute expected results dynamically from the input file
    edges = defaultdict(int)
    nodes = set()

    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            source = row['source']
            target = row['target']
            amount = int(row['amount'])

            nodes.add(source)
            nodes.add(target)

            # Deduplication: keep max amount
            if amount > edges[(source, target)]:
                edges[(source, target)] = amount

    # Group incoming edges by target
    incoming = defaultdict(list)
    for (source, target), amount in edges.items():
        incoming[target].append(amount)

    expected_metrics = {}
    for node in nodes:
        weights = sorted(incoming[node], reverse=True)
        top3_sum = sum(weights[:3])
        expected_metrics[node] = top3_sum

    expected_sorted_nodes = sorted(list(nodes))

    # 2. Read the actual output file
    actual_rows = []
    with open(output_file, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) > 0, "The output file is empty."

    header = content[0].strip()
    assert header == "node_id,top3_in_weight_sum", f"Incorrect header in output file: {header}"

    actual_data = content[1:]
    assert len(actual_data) == len(expected_sorted_nodes), f"Expected {len(expected_sorted_nodes)} data rows, but found {len(actual_data)}."

    for i, row in enumerate(actual_data):
        parts = row.strip().split(',')
        assert len(parts) == 2, f"Row {i+1} is malformed: {row}"

        node_id, val_str = parts
        expected_node = expected_sorted_nodes[i]

        assert node_id == expected_node, f"Expected node '{expected_node}' at row {i+1}, but found '{node_id}'. Rows must be sorted alphabetically."

        try:
            val = int(val_str)
        except ValueError:
            pytest.fail(f"Value for node {node_id} is not an integer: {val_str}")

        expected_val = expected_metrics[node_id]
        assert val == expected_val, f"Incorrect sum for node {node_id}. Expected {expected_val}, got {val}."


def expected_for(rows):
    edges = {}
    nodes = set()
    for source, target, amount, _timestamp in rows:
        nodes.add(source)
        nodes.add(target)
        key = (source, target)
        edges[key] = max(edges.get(key, amount), amount)

    incoming = defaultdict(list)
    for (_source, target), amount in edges.items():
        incoming[target].append(amount)

    return [(node, sum(sorted(incoming[node], reverse=True)[:3])) for node in sorted(nodes)]


def write_input(rows):
    with open(INPUT_FILE, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target", "amount", "timestamp"])
        writer.writerows(rows)


def assert_generated_output(rows, label):
    expected = expected_for(rows)
    assert os.path.isfile(OUTPUT_FILE), f"{label} did not create node_metrics.csv"
    with open(OUTPUT_FILE, newline="") as f:
        parsed = list(csv.reader(f))

    assert parsed, f"{label} produced an empty output file"
    assert parsed[0] == ["node_id", "top3_in_weight_sum"], f"{label} produced an incorrect header"
    assert len(parsed) == len(expected) + 1, f"{label} produced the wrong number of rows"

    actual = []
    for row in parsed[1:]:
        assert len(row) == 2, f"{label} produced a malformed row: {row}"
        try:
            value = int(row[1])
        except ValueError:
            pytest.fail(f"{label} produced a non-integer metric: {row[1]}")
        actual.append((row[0], value))
    assert actual == expected, f"{label} did not implement deduplication, top-3 aggregation, and sorting correctly"


def run_and_check(executable, rows, label):
    write_input(rows)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    subprocess.run([executable], cwd="/home/user", check=True, timeout=15)
    assert_generated_output(rows, label)


def test_cpp_artifacts_compile_and_execute_on_fresh_input():
    """Require the requested C++ source and executable, then exercise both on fresh data."""
    for path, description in ((SOURCE_FILE, "C++ source"), (EXECUTABLE_FILE, "compiled executable")):
        assert os.path.exists(path), f"Missing required {description}: {path}"
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f"Required {description} is not a regular file: {path}"

    assert os.access(EXECUTABLE_FILE, os.X_OK), "The graph_etl artifact is not executable."
    with open(EXECUTABLE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The graph_etl artifact is not a compiled executable."

    verified_executable = "/tmp/verified_graph_etl"
    subprocess.run(
        ["g++", "-O3", "-std=c++17", "-o", verified_executable, SOURCE_FILE],
        cwd="/home/user",
        check=True,
        timeout=30,
    )

    token = secrets.token_hex(6)
    names = [f"n_{token}_{i}" for i in range(8)]
    amounts = [secrets.randbelow(800) + 20 for _ in range(10)]
    rows = [
        (names[0], names[4], amounts[0], 1),
        (names[0], names[4], amounts[0] + 900, 2),
        (names[1], names[4], amounts[1], 3),
        (names[2], names[4], amounts[2], 4),
        (names[3], names[4], amounts[3], 5),
        (names[5], names[4], amounts[4], 6),
        (names[4], names[2], amounts[5], 7),
        (names[6], names[2], amounts[6], 8),
        (names[7], names[6], amounts[7], 9),
        (names[7], names[6], amounts[7] + 500, 10),
        (names[1], names[5], amounts[8], 11),
        (names[3], names[5], amounts[9], 12),
    ]

    original_input = open(INPUT_FILE, "rb").read()
    original_output = open(OUTPUT_FILE, "rb").read() if os.path.exists(OUTPUT_FILE) else None
    try:
        run_and_check(EXECUTABLE_FILE, rows, "submitted graph_etl executable")
        rows_for_source = list(reversed(rows))
        run_and_check(verified_executable, rows_for_source, "program compiled from graph_etl.cpp")
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
        else:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
