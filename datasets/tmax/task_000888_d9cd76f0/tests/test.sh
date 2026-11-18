#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import uuid
import pytest

EXECUTABLE_PATH = "/home/user/profile_analyzer"
CLEAN_CORPUS_DIR = "/app/corpora_hidden/clean"
EVIL_CORPUS_DIR = "/app/corpora_hidden/evil"
TIMEOUT_THRESHOLD = 25000.0


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "profile_analyzer must be a compiled executable"


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory"

    failures = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "CLEAN":
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files misclassified (should be CLEAN). Offending files: {', '.join(failures)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory"

    failures = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "EVIL":
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed (should be EVIL). Offending files: {', '.join(failures)}")


def expected_cost(costs, edges):
    """Solve E[i] = cost[i] + sum(P(i,j) * E[j]) independently."""
    n = len(costs)
    matrix = [[0.0] * (n + 1) for _ in range(n)]
    outgoing = [[] for _ in range(n)]
    for src, dst, probability in edges:
        outgoing[src].append((dst, probability))

    for i in range(n):
        matrix[i][i] = 1.0
        matrix[i][n] = costs[i]
        if i != n - 1:
            assert outgoing[i], f"non-exit node {i} has no outgoing edge"
            assert abs(sum(p for _, p in outgoing[i]) - 1.0) < 1e-9
            for dst, probability in outgoing[i]:
                matrix[i][dst] -= probability

    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(matrix[row][col]))
        assert abs(matrix[pivot][col]) > 1e-12, "generated graph has no finite expectation"
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        divisor = matrix[col][col]
        matrix[col] = [value / divisor for value in matrix[col]]
        for row in range(n):
            if row == col:
                continue
            factor = matrix[row][col]
            if factor:
                matrix[row] = [a - factor * b for a, b in zip(matrix[row], matrix[col])]
    return matrix[0][n]


def write_graph(directory, costs, edges):
    path = os.path.join(directory, uuid.uuid4().hex + ".dat")
    with open(path, "w") as f:
        f.write(f"{len(costs)}\n")
        for cost in costs:
            f.write(f"{cost:.12f}\n")
        for src, dst, probability in edges:
            f.write(f"{src} {dst} {probability:.12f}\n")
    return path


def test_generated_mixed_graphs():
    rng = secrets.SystemRandom()
    clean_loop_probability = round(rng.uniform(0.93, 0.95), 6)
    evil_loop_probability = round(rng.uniform(0.97, 0.98), 6)
    rare_clean_probability = round(rng.uniform(0.0005, 0.0015), 6)
    rare_evil_probability = round(rng.uniform(0.014, 0.018), 6)

    cases = [
        # Strict threshold: equality is CLEAN, while even a small excess is EVIL.
        ([25000.0, 0.0], [(0, 1, 1.0)]),
        ([25000.0 + rng.uniform(0.25, 2.0), 0.0], [(0, 1, 1.0)]),
        # An unreachable high-cost node must not affect the simulated path.
        ([rng.uniform(50.0, 200.0), rng.uniform(50.0, 200.0), 1.0e9, 0.0],
         [(0, 1, 1.0), (1, 3, 1.0), (2, 3, 1.0)]),
        # Repeated visits make these otherwise similar graphs fall on opposite sides.
        ([0.0, 1000.0, 0.0],
         [(0, 1, 1.0), (1, 1, clean_loop_probability), (1, 2, 1.0 - clean_loop_probability)]),
        ([0.0, 1000.0, 0.0],
         [(0, 1, 1.0), (1, 1, evil_loop_probability), (1, 2, 1.0 - evil_loop_probability)]),
        # Rare branches exercise aggregation over many Monte Carlo runs.
        ([0.0, 5000000.0, 0.0, 0.0],
         [(0, 1, rare_clean_probability), (0, 2, 1.0 - rare_clean_probability),
          (1, 3, 1.0), (2, 3, 1.0)]),
        ([0.0, 5000000.0, 0.0, 0.0],
         [(0, 1, rare_evil_probability), (0, 2, 1.0 - rare_evil_probability),
          (1, 3, 1.0), (2, 3, 1.0)]),
        # A randomized deterministic path prevents reliance on the shipped examples.
        ([rng.uniform(9000.0, 11000.0), rng.uniform(9000.0, 11000.0), 0.0],
         [(0, 1, 1.0), (1, 2, 1.0)]),
    ]

    with tempfile.TemporaryDirectory(prefix="profile_cases_") as directory:
        generated = []
        for costs, edges in cases:
            expectation = expected_cost(costs, edges)
            label = "EVIL" if expectation > TIMEOUT_THRESHOLD else "CLEAN"
            generated.append((write_graph(directory, costs, edges), label, expectation))

        assert {label for _, label, _ in generated} == {"CLEAN", "EVIL"}
        random.SystemRandom().shuffle(generated)

        failures = []
        for path, expected, expectation in generated:
            try:
                result = subprocess.run(
                    [EXECUTABLE_PATH, path], capture_output=True, text=True, timeout=20
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue
            if result.returncode != 0:
                failures.append(f"{os.path.basename(path)} exited {result.returncode}")
            elif result.stdout != expected + "\n":
                failures.append(
                    f"{os.path.basename(path)} expected {expected} for mean {expectation:.3f}, "
                    f"got {result.stdout!r}"
                )

        if failures:
            pytest.fail("Generated graph failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
