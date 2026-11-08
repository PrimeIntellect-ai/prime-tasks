#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

import pytest

PROJECT = "/home/user/data_prep"
MAIN_GO = os.path.join(PROJECT, "main.go")
MATRIX_CSV = os.path.join(PROJECT, "matrix.csv")
TRACE_FILE = "/home/user/trace.txt"
GO = "/usr/local/go/bin/go"


def run_program():
    if os.path.exists(TRACE_FILE):
        os.remove(TRACE_FILE)

    result = subprocess.run(
        [GO, "run", "main.go"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "main.go failed when executed:\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(TRACE_FILE), (
        f"File {TRACE_FILE} does not exist. The script must create this file."
    )

    with open(TRACE_FILE, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", content), (
        f"Trace must be formatted to exactly 4 decimal places, got {content!r}."
    )
    return content


def orthogonal_matrix(rng, n=4):
    columns = []
    for _ in range(n):
        while True:
            v = [rng.uniform(-1.0, 1.0) for _ in range(n)]
            for q in columns:
                projection = sum(v[i] * q[i] for i in range(n))
                v = [v[i] - projection * q[i] for i in range(n)]
            norm = math.sqrt(sum(x * x for x in v))
            if norm > 1e-8:
                columns.append([x / norm for x in v])
                break
    return [[columns[j][i] for j in range(n)] for i in range(n)]


def covariance_with_singular_values(rng, values):
    q = orthogonal_matrix(rng, len(values))
    n = len(values)
    return [
        [sum(q[i][k] * values[k] * q[j][k] for k in range(n)) for j in range(n)]
        for i in range(n)
    ]


def write_matrix(matrix):
    with open(MATRIX_CSV, "w") as f:
        for row in matrix:
            f.write(",".join(format(value, ".17g") for value in row) + "\n")


def test_main_go_exists_and_uses_gonum_svd():
    assert os.path.isfile(MAIN_GO), f"File {MAIN_GO} is missing."
    with open(MAIN_GO, "r") as f:
        source = f.read()

    assert re.search(r"\bpackage\s+main\b", source), "main.go must be a Go main package."
    assert re.search(r"\bfunc\s+main\s*\(", source), "main.go must define main()."
    assert "gonum.org/v1/gonum/mat" in source, "The implementation must use Gonum mat."
    assert re.search(r"\bSVD\b", source), "The implementation must compute an SVD."
    assert "Factorize" in source and "Values" in source, (
        "The Gonum SVD must be factorized and its singular values inspected."
    )
    assert "UTo" in source and "VTo" in source, (
        "The regularized matrix must be reconstructed from the SVD's U and V factors."
    )


def test_program_regularizes_runtime_inputs_and_generates_original_trace():
    with open(MATRIX_CSV, "rb") as f:
        original_matrix = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = [
        [rng.uniform(0.002, 0.06), rng.uniform(0.065, 0.095),
         rng.uniform(0.3, 2.0), rng.uniform(2.5, 8.0)],
        [rng.uniform(0.001, 0.04), rng.uniform(0.12, 0.7),
         rng.uniform(1.0, 4.0), rng.uniform(5.0, 12.0)],
    ]

    try:
        for singular_values in cases:
            write_matrix(covariance_with_singular_values(rng, singular_values))
            expected = f"{sum(max(value, 0.1) for value in singular_values):.4f}"
            actual = run_program()
            assert actual == expected, (
                f"For a runtime-generated covariance matrix, expected trace "
                f"{expected!r}, but got {actual!r}."
            )
    finally:
        with open(MATRIX_CSV, "wb") as f:
            f.write(original_matrix)

    # The submitted program must also be run against the provided matrix.
    run_program()


def test_trace_file_exists_and_correct():
    trace_file_path = "/home/user/trace.txt"

    assert os.path.isfile(trace_file_path), f"File {trace_file_path} does not exist. The script must create this file."

    with open(trace_file_path, 'r') as f:
        content = f.read().strip()

    expected_trace = "204.2000"
    assert content == expected_trace, f"Expected trace value to be '{expected_trace}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
