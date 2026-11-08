#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

import pytest

SOURCE = "/home/user/analyzer.cpp"
BINARY = "/tmp/analyzer_verifier"
GRAPH = "/home/user/transition_graph.txt"
EMPIRICAL = "/home/user/empirical.txt"
RESULTS = "/home/user/results.log"

ORIGINAL_GRAPH = """A B 0.6
A C 0.4
B A 0.3
B C 0.7
C A 0.5
C B 0.5
"""

ORIGINAL_EMPIRICAL = """A 0.30
B 0.35
C 0.35
"""


def run_analyzer():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"analyzer exited with status {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Expected output file {RESULTS} is missing."


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_original_case():
    assert os.path.isfile(SOURCE), f"Expected C++ source file {SOURCE} is missing."
    assert os.path.getsize(SOURCE) > 0, f"Expected C++ source file {SOURCE} is empty."

    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compiled.returncode == 0, f"Compilation failed: {compiled.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable."
    )

    with open(GRAPH, "w") as f:
        f.write(ORIGINAL_GRAPH)
    with open(EMPIRICAL, "w") as f:
        f.write(ORIGINAL_EMPIRICAL)
    run_analyzer()


def test_results_log_exists():
    filepath = "/home/user/results.log"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing."


def test_results_log_content():
    filepath = "/home/user/results.log"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing."

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Stationary A: 0.2863",
        "Stationary B: 0.3524",
        "Stationary C: 0.3612",
        "KL_Divergence: 0.0005"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {filepath}."

    assert len(lines) == 4, f"Expected exactly 4 lines in {filepath}, but found {len(lines)}."
    assert lines == expected_lines, f"Contents of {filepath} do not match the expected output exactly."


def positive_composition(rng, total, count):
    cuts = sorted(rng.sample(range(1, total), count - 1))
    points = [0] + cuts + [total]
    return [points[i + 1] - points[i] for i in range(count)]


def reference_output(nodes, matrix, empirical):
    n = len(nodes)
    pi = [1.0 / n] * n
    while True:
        nxt = [0.0] * n
        for i in range(n):
            for j in range(n):
                nxt[j] += pi[i] * matrix[i][j]
        difference = max(abs(nxt[i] - pi[i]) for i in range(n))
        pi = nxt
        if difference < 1e-7:
            break

    kl = sum(empirical[i] * math.log(empirical[i] / pi[i]) for i in range(n))
    return [f"Stationary {nodes[i]}: {pi[i]:.4f}" for i in range(n)] + [
        f"KL_Divergence: {kl:.4f}"
    ]


def test_analyzer_computes_unseen_inputs():
    rng = random.SystemRandom()

    for _ in range(4):
        count = rng.randint(3, 6)
        nodes = sorted(rng.sample(list("DEFGHIJKLMNOPQRSTUVWXYZ"), count))

        matrix = []
        graph_lines = []
        for source_index, source in enumerate(nodes):
            weights = positive_composition(rng, 10000, count)
            row = [weight / 10000.0 for weight in weights]
            matrix.append(row)
            for target_index, target in enumerate(nodes):
                graph_lines.append(
                    f"{source} {target} {row[target_index]:.4f}"
                )
        rng.shuffle(graph_lines)

        empirical_weights = positive_composition(rng, 10000, count)
        empirical = [weight / 10000.0 for weight in empirical_weights]

        with open(GRAPH, "w") as f:
            f.write("\n".join(graph_lines) + "\n")
        with open(EMPIRICAL, "w") as f:
            for node, value in zip(nodes, empirical):
                f.write(f"{node} {value:.4f}\n")

        expected_lines = reference_output(nodes, matrix, empirical)
        run_analyzer()

        with open(RESULTS, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        assert len(lines) == count + 1, (
            f"Expected exactly {count + 1} output lines, found {len(lines)}."
        )
        for line in lines[:-1]:
            assert re.fullmatch(r"Stationary [^:]+: -?\d+\.\d{4}", line), (
                f"Invalid stationary-distribution output format: {line!r}"
            )
        assert re.fullmatch(r"KL_Divergence: -?\d+\.\d{4}", lines[-1]), (
            f"Invalid KL-divergence output format: {lines[-1]!r}"
        )
        assert lines == expected_lines, (
            "Analyzer output for a verifier-generated graph was incorrect.\n"
            f"Expected: {expected_lines}\nActual: {lines}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
