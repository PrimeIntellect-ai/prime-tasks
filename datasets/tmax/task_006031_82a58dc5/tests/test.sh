#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import pytest

SOURCE_PATH = "/home/user/mcmc_graph.c"
BINARY_PATH = "/home/user/mcmc_graph"
NETWORK_PATH = "/home/user/network.txt"
RESULTS_PATH = "/home/user/results.txt"

CANONICAL_NETWORK = b"""0 1
1 2
2 0
2 3
3 4
4 5
5 3
5 6
6 7
7 5
"""


def run_program():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{BINARY_PATH} exited with status {completed.returncode}. "
        f"stderr: {completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(RESULTS_PATH), f"{BINARY_PATH} did not create {RESULTS_PATH}."


def parse_results(strict_four_decimals=False):
    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULTS_PATH}, but found {len(lines)}."
    decimals = r"[0-9]+\.[0-9]{4}" if strict_four_decimals else r"[0-9]+\.[0-9]+"
    analytical_match = re.match(rf"^Analytical:\s*({decimals})$", lines[0])
    assert analytical_match, f"First line '{lines[0]}' does not match the expected format 'Analytical: 0.XXXX'."
    mcmc_match = re.match(rf"^MCMC:\s*({decimals})$", lines[1])
    assert mcmc_match, f"Second line '{lines[1]}' does not match the expected format 'MCMC: 0.XXXX'."
    return float(analytical_match.group(1)), float(mcmc_match.group(1))


def test_source_code_exists():
    assert os.path.exists(SOURCE_PATH), "The C source file /home/user/mcmc_graph.c is missing."
    assert os.path.isfile(SOURCE_PATH), "/home/user/mcmc_graph.c is not a file."


def test_compiled_binary_exists():
    assert os.path.exists(BINARY_PATH), f"The compiled binary {BINARY_PATH} is missing."
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"The file {BINARY_PATH} is not executable."


def test_source_compiles_and_binary_runs():
    with open(NETWORK_PATH, "wb") as f:
        f.write(CANONICAL_NETWORK)

    completed = subprocess.run(
        ["gcc", "-O3", "-o", BINARY_PATH, SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, (
        f"Failed to compile {SOURCE_PATH} with the required command. "
        f"stderr: {completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)
    run_program()


def test_results_file_correctness():
    assert os.path.exists(RESULTS_PATH), f"The results file {RESULTS_PATH} is missing."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."

    analytical_val, mcmc_val = parse_results()
    assert abs(analytical_val - 0.2000) < 1e-5, f"Expected Analytical value to be 0.2000, got {analytical_val:.4f}."
    assert 0.1900 <= mcmc_val <= 0.2100, f"Expected MCMC value to be close to 0.2000 (between 0.1900 and 0.2100), got {mcmc_val:.4f}."


def make_hidden_graph(rng, used_probabilities):
    while True:
        n = rng.randrange(9, 15)
        edges = {(i, i + 1) for i in range(n - 1)}
        edges.add((0, 2))  # Together with 0-1-2, guarantees non-bipartiteness.

        for a in range(n):
            for b in range(a + 1, n):
                if (a, b) not in edges and rng.randrange(100) < 38:
                    edges.add((a, b))

        degree5 = sum(1 for a, b in edges if a == 5 or b == 5)
        expected = degree5 / (2.0 * len(edges))
        rounded = f"{expected:.4f}"
        if not (0.17 <= expected <= 0.23) and rounded not in used_probabilities:
            used_probabilities.add(rounded)
            edge_list = list(edges)
            rng.shuffle(edge_list)
            return edge_list, expected


def test_binary_parses_hidden_graphs_and_performs_mcmc():
    rng = secrets.SystemRandom()
    with open(NETWORK_PATH, "rb") as f:
        saved_network = f.read()
    saved_results = None
    if os.path.isfile(RESULTS_PATH):
        with open(RESULTS_PATH, "rb") as f:
            saved_results = f.read()

    used_probabilities = set()
    saw_nonexact_mcmc = False
    try:
        for _ in range(5):
            edges, expected = make_hidden_graph(rng, used_probabilities)
            with open(NETWORK_PATH, "w") as f:
                for a, b in edges:
                    f.write(f"{a} {b}\n")

            run_program()
            analytical_val, mcmc_val = parse_results(strict_four_decimals=True)

            assert abs(analytical_val - expected) <= 0.000051, (
                f"Analytical result {analytical_val:.4f} does not equal "
                f"deg(5)/(2|E|) = {expected:.8f} for the supplied graph."
            )
            assert abs(mcmc_val - expected) <= 0.0100, (
                f"MCMC result {mcmc_val:.4f} is not close to the stationary "
                f"probability {expected:.8f} for the supplied graph."
            )
            if mcmc_val != analytical_val:
                saw_nonexact_mcmc = True

        assert saw_nonexact_mcmc, (
            "Across all hidden graphs, MCMC was always exactly the rounded analytical value; "
            "the required empirical random-walk estimate was not demonstrated."
        )
    finally:
        with open(NETWORK_PATH, "wb") as f:
            f.write(saved_network)
        if saved_results is None:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
        else:
            with open(RESULTS_PATH, "wb") as f:
                f.write(saved_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
