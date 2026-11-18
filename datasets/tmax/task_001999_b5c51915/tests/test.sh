#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import math
import os
import re
import subprocess

GO_FILE = "/home/user/generate_data.go"
CSV_FILE = "/home/user/training_data.csv"
GRAPH_FILE = "/home/user/graph.txt"
BINARY = "/tmp/submission_generate_data"
HEADER = ["time", "node0", "node1", "node2", "node3"]
ORIGINAL_EDGES = [(0, 1), (1, 2), (2, 3), (3, 0)]
FOUR_DECIMALS = re.compile(r"^-?\d+\.\d{4}$")


def read_csv_file():
    assert os.path.exists(CSV_FILE), f"The output CSV file {CSV_FILE} does not exist."
    assert os.path.isfile(CSV_FILE), f"The path {CSV_FILE} is not a file."
    with open(CSV_FILE, newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError("The CSV file is empty.")
        rows = list(reader)
    assert header == HEADER, f"Header is incorrect. Expected {HEADER}, got {header}"
    return rows


def retain_original_assertions():
    rows = read_csv_file()
    num_rows = len(rows)
    assert num_rows in [1000, 1001], f"Expected 1000 or 1001 data rows, got {num_rows}."

    try:
        first_row = [float(x) for x in rows[0]]
    except ValueError:
        raise AssertionError("First row contains non-numeric values.")
    assert abs(first_row[0] - 0.0) < 1e-4
    assert abs(first_row[1] - 10.0) < 1e-4
    assert abs(first_row[2] - 0.0) < 1e-4
    assert abs(first_row[3] - 0.0) < 1e-4
    assert abs(first_row[4] - 0.0) < 1e-4

    try:
        second_row = [float(x) for x in rows[1]]
    except ValueError:
        raise AssertionError("Second row contains non-numeric values.")
    assert abs(second_row[1] - 9.8) < 1e-3
    assert abs(second_row[2] - 0.1) < 1e-3
    assert abs(second_row[3] - 0.0) < 1e-3
    assert abs(second_row[4] - 0.1) < 1e-3

    try:
        last_row = [float(x) for x in rows[-1]]
    except ValueError:
        raise AssertionError("Last row contains non-numeric values.")
    for i in range(1, 5):
        assert abs(last_row[i] - 2.5) <= 0.1, \
            f"Node {i-1} did not converge to ~2.5, got {last_row[i]}"

    for val in rows[0]:
        if "." in val:
            assert len(val.split(".")[1]) == 4, \
                f"Values must be formatted to 4 decimal places, got '{val}'"


def connected(edges):
    adjacency = [set() for _ in range(4)]
    for a, b in edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    seen = {0}
    stack = [0]
    while stack:
        node = stack.pop()
        for neighbor in adjacency[node] - seen:
            seen.add(neighbor)
            stack.append(neighbor)
    return len(seen) == 4


def expected_rows(edges):
    adjacency = [[] for _ in range(4)]
    for a, b in edges:
        adjacency[a].append(b)
        adjacency[b].append(a)

    values = [10.0, 0.0, 0.0, 0.0]
    result = []
    for step in range(1001):
        result.append([step * 0.01] + values[:])
        if step < 1000:
            derivative = []
            for node in range(4):
                derivative.append(
                    sum(values[nbr] for nbr in adjacency[node])
                    - len(adjacency[node]) * values[node]
                )
            values = [values[i] + 0.01 * derivative[i] for i in range(4)]
    return result


def validate_complete_output(edges):
    rows = read_csv_file()
    assert len(rows) in [1000, 1001], f"Expected 1000 or 1001 data rows, got {len(rows)}."
    assert len(rows) == 1001, \
        f"1000 Euler steps including both t=0.00 and t=10.00 require 1001 rows, got {len(rows)}."

    expected = expected_rows(edges)
    for row_index, (row, wanted) in enumerate(zip(rows, expected)):
        assert len(row) == 5, f"Row {row_index} has {len(row)} columns instead of 5."
        for column_index, text in enumerate(row):
            assert FOUR_DECIMALS.fullmatch(text), \
                f"Row {row_index}, column {column_index} is not formatted to 4 decimal places: {text!r}"
            try:
                actual = float(text)
            except ValueError:
                raise AssertionError(f"Non-numeric value at row {row_index}, column {column_index}: {text!r}")
            assert math.isfinite(actual), \
                f"Non-finite value at row {row_index}, column {column_index}."
            assert abs(actual - wanted[column_index]) <= 0.000051, \
                (f"Incorrect Euler value at row {row_index}, column {column_index}: "
                 f"got {actual}, expected {wanted[column_index]:.8f}")

    for i in range(1, 5):
        assert abs(float(rows[-1][i]) - 2.5) <= 0.1, \
            f"Node {i-1} did not converge to ~2.5, got {rows[-1][i]}"


def write_graph(edges):
    with open(GRAPH_FILE, "w") as f:
        for a, b in edges:
            f.write(f"{a},{b}\n")


def run_case(edges):
    write_graph(edges)
    if os.path.lexists(CSV_FILE):
        os.remove(CSV_FILE)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, \
        f"Program failed for graph {edges}:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.isfile(CSV_FILE), "Running the Go program did not create training_data.csv."
    validate_complete_output(edges)


def test_submission():
    assert os.path.exists(GO_FILE), f"The Go source file {GO_FILE} does not exist."
    assert os.path.isfile(GO_FILE), f"The path {GO_FILE} is not a file."

    # Preserve all checks made against the dataset supplied by the agent.
    retain_original_assertions()

    build = subprocess.run(
        ["go", "build", "-o", BINARY, GO_FILE], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert build.returncode == 0, \
        f"generate_data.go did not compile:\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"

    all_edges = list(itertools.combinations(range(4), 2))
    graph_cases = []
    for mask in range(1, 1 << len(all_edges)):
        edges = [all_edges[i] for i in range(len(all_edges)) if mask & (1 << i)]
        if connected(edges):
            graph_cases.append(edges)

    # Exercise graph parsing and every output row on every connected simple
    # four-node topology. Finish on the originally supplied graph.
    original_set = {tuple(sorted(edge)) for edge in ORIGINAL_EDGES}
    graph_cases = [g for g in graph_cases if {tuple(sorted(e)) for e in g} != original_set]
    try:
        for edges in graph_cases:
            run_case(edges)
        run_case(ORIGINAL_EDGES)
    finally:
        write_graph(ORIGINAL_EDGES)


if __name__ == "__main__":
    test_submission()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
