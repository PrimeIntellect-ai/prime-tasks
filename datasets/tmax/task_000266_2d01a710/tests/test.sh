#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SOURCE = "/home/user/process_graph.c"
BINARY = "/home/user/process_graph"
RAW_EDGES = "/home/user/raw_edges.txt"
RESULTS = "/home/user/page2_results.txt"

ORIGINAL_EDGES = """1 2
2 3
1 4
4 5
1 5
2 4
2 5
6 7
7 8
6 8
6 9
7 9
8 9
10 11
1 10
3 4
"""


def expected_lines(edges):
    degrees = {}
    for source, target in edges:
        degrees[source] = degrees.get(source, 0) + 1
        degrees[target] = degrees.get(target, 0) + 1
    ordered = sorted(
        ((node, degree) for node, degree in degrees.items() if degree >= 3),
        key=lambda item: (-item[1], item[0]),
    )
    return [f"{node} {degree}" for node, degree in ordered[5:10]]


def write_edges(edges):
    with open(RAW_EDGES, "w") as f:
        for source, target in edges:
            f.write(f"{source} {target}\n")


def run_program():
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Program did not create {RESULTS}"
    with open(RESULTS, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_c_source_exists():
    path = "/home/user/process_graph.c"
    assert os.path.isfile(path), f"C source file {path} does not exist. You must write your solution in this file."


def test_program_compiles_and_processes_inputs():
    if os.path.lexists(BINARY):
        os.remove(BINARY)
    completed = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
    )
    assert completed.returncode == 0, (
        f"gcc failed with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "gcc did not produce an executable program"

    rng = secrets.SystemRandom()
    try:
        for node_count, extra_count in ((11, 7), (14, 16), (19, 25)):
            ids = rng.sample(range(100, 1000000), node_count + 3)
            main_ids = ids[:node_count]
            edges = []

            # Two copies of a cycle give every main node degree four.
            for _ in range(2):
                for i, node in enumerate(main_ids):
                    edges.append((node, main_ids[(i + 1) % node_count]))

            for _ in range(extra_count):
                edges.append((rng.choice(main_ids), rng.choice(main_ids)))

            # Include nodes below the filtering threshold, including a self-loop.
            edges.append((ids[-3], ids[-2]))
            edges.append((ids[-1], ids[-1]))
            rng.shuffle(edges)

            actual = run_program() if not write_edges(edges) else None
            expected = expected_lines(edges)
            assert actual == expected, (
                "Program produced incorrect Page 2 output for a generated edge list.\n"
                f"Expected: {expected}\nGot: {actual}"
            )
    finally:
        with open(RAW_EDGES, "w") as f:
            f.write(ORIGINAL_EDGES)
        run_program()


def test_page2_results_exists():
    path = "/home/user/page2_results.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist. Did your program run and produce it?"


def test_page2_results_content():
    path = "/home/user/page2_results.txt"
    expected_lines_fixed = [
        "7 3",
        "8 3",
        "9 3"
    ]

    with open(path, "r") as f:
        content = [line.strip() for line in f.readlines() if line.strip()]

    assert content == expected_lines_fixed, f"Content of {path} is incorrect.\nExpected:\n{expected_lines_fixed}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
