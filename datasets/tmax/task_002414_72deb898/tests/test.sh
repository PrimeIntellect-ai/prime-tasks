#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
from collections import defaultdict

import pytest

SOURCE = "/home/user/process_network.cpp"
EXECUTABLE = "/home/user/process_network"
NETWORK = "/home/user/network.csv"
WINDOW = "/home/user/window_results.csv"
GRAPH = "/home/user/graph_results.csv"
REBUILT = "/tmp/process_network_verified"

FIXTURE = [
    ("A", "B", 10, 1),
    ("A", "C", 5, 2),
    ("B", "D", 8, 3),
    ("C", "D", 15, 4),
    ("D", "E", 2, 5),
    ("A", "F", 20, 6),
    ("F", "G", 1, 7),
    ("A", "H", 10, 8),
    ("H", "I", 12, 9),
    ("A", "J", 5, 10),
]


def write_network(rows):
    with open(NETWORK, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source", "target", "weight", "timestamp"])
        writer.writerows(rows)


def expected_outputs(rows):
    by_source = defaultdict(list)
    for source, target, weight, timestamp in rows:
        by_source[source].append((target, weight, timestamp))

    window_rows = []
    for source, interactions in by_source.items():
        ordered_keys = sorted(
            {(weight, timestamp) for _, weight, timestamp in interactions},
            key=lambda item: (-item[0], item[1]),
        )
        ranks = {key: index + 1 for index, key in enumerate(ordered_keys)}
        for target, weight, timestamp in interactions:
            rank = ranks[(weight, timestamp)]
            if rank <= 2:
                window_rows.append((source, target, weight, rank))
    window_rows.sort(key=lambda row: (row[0], row[3], row[1]))

    outgoing = defaultdict(list)
    for source, target, weight, _ in rows:
        outgoing[source].append((target, weight))

    best = {}
    for middle, first_weight in outgoing.get("A", []):
        for destination, second_weight in outgoing.get(middle, []):
            bottleneck = min(first_weight, second_weight)
            best[destination] = max(best.get(destination, bottleneck), bottleneck)
    graph_rows = sorted(best.items())

    return ([f"{s},{t},{w},{r}" for s, t, w, r in window_rows],
            [f"{d},{w}" for d, w in graph_rows])


def read_nonempty_lines(path):
    assert os.path.isfile(path), f"The required output file {path} does not exist."
    with open(path, "r", newline="") as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(program, rows, expected_window=None, expected_graph=None):
    write_network(rows)
    for path in (WINDOW, GRAPH):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}. stderr: {result.stderr}"
    )

    if expected_window is None or expected_graph is None:
        expected_window, expected_graph = expected_outputs(rows)

    actual_window = read_nonempty_lines(WINDOW)
    actual_graph = read_nonempty_lines(GRAPH)
    assert actual_window == expected_window, (
        f"Content of {WINDOW} is incorrect. Expected: {expected_window}, "
        f"but got: {actual_window}"
    )
    assert actual_graph == expected_graph, (
        f"Content of {GRAPH} is incorrect. Expected: {expected_graph}, "
        f"but got: {actual_graph}"
    )


def randomized_case(rng, case_number):
    timestamp_pool = list(range(1000 + case_number * 100, 1080 + case_number * 100))
    rng.shuffle(timestamp_pool)

    pairs = [
        ("A", "B"), ("A", "C"), ("A", "D"), ("A", "E"),
        ("B", "F"), ("B", "G"), ("C", "F"), ("C", "H"),
        ("D", "G"), ("D", "I"), ("E", "H"), ("E", "I"),
        ("F", "J"), ("G", "J"), ("H", "K"), ("I", "K"),
    ]
    optional = [
        ("B", "H"), ("C", "G"), ("D", "F"), ("E", "G"),
        ("F", "K"), ("G", "L"), ("H", "L"), ("I", "L"),
    ]
    pairs.extend(pair for pair in optional if rng.choice([True, False]))

    rows = []
    for index, (source, target) in enumerate(pairs):
        weight = rng.randint(1, 50)
        timestamp = timestamp_pool[index]
        rows.append((source, target, weight, timestamp))

    # Force equal weights with different timestamps so the timestamp component
    # of the DENSE_RANK ordering is exercised.
    tied_weight = rng.randint(51, 80)
    rows[0] = ("A", "B", tied_weight, timestamp_pool[0])
    rows[1] = ("A", "C", tied_weight, timestamp_pool[1])
    rng.shuffle(rows)
    return rows


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE), "The C++ source file /home/user/process_network.cpp does not exist."


def test_cpp_executable_exists():
    assert os.path.isfile(EXECUTABLE), "The compiled executable /home/user/process_network does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "The file /home/user/process_network is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The required executable is not a compiled ELF program."


def test_program_execution_and_results():
    with open(NETWORK, "rb") as f:
        original_network = f.read()

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-lsqlite3", "-o", REBUILT],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            f"The submitted C++ source does not compile: {compile_result.stderr}"
        )

        symbols = subprocess.run(
            ["nm", "-D", REBUILT], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10, check=True
        ).stdout
        assert "sqlite3_" in symbols, "The rebuilt program does not use the SQLite3 API."

        fixture_window = [
            "A,F,20,1",
            "A,B,10,2",
            "B,D,8,1",
            "C,D,15,1",
            "D,E,2,1",
            "F,G,1,1",
            "H,I,12,1",
        ]
        fixture_graph = ["D,8", "G,1", "I,10"]

        # Execute both the delivered binary and a verifier-built binary from the
        # submitted source, retaining the original fixed-fixture assertions.
        run_and_check(EXECUTABLE, FIXTURE, fixture_window, fixture_graph)
        run_and_check(REBUILT, FIXTURE, fixture_window, fixture_graph)

        rng = random.Random(secrets.randbits(128))
        for case_number in range(3):
            rows = randomized_case(rng, case_number)
            run_and_check(EXECUTABLE, rows)
            run_and_check(REBUILT, rows)
    finally:
        with open(NETWORK, "wb") as f:
            f.write(original_network)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
