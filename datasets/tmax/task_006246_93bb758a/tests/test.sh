#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import pytest

PROJECT = "/home/user/stiff_ode"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
MATRIX = os.path.join(PROJECT, "matrix_A.txt")
VECTOR = os.path.join(PROJECT, "vector_b.txt")
SOLUTION = os.path.join(PROJECT, "solution.txt")


def run_project():
    if os.path.exists(SOLUTION):
        os.remove(SOLUTION)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert result.returncode == 0, f"cargo run failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SOLUTION), f"File {SOLUTION} is missing. The Rust program must create it."
    with open(SOLUTION, "r") as f:
        return f.read().strip()


def random_orthogonal(n):
    rng = secrets.SystemRandom()
    columns = []
    while len(columns) < n:
        v = [rng.uniform(-1.0, 1.0) for _ in range(n)]
        for q in columns:
            projection = sum(v[i] * q[i] for i in range(n))
            v = [v[i] - projection * q[i] for i in range(n)]
        norm = math.sqrt(sum(value * value for value in v))
        if norm > 1e-6:
            columns.append([value / norm for value in v])
    return columns


def make_derived_case():
    # A = Q diag(s) Q^T has known singular vectors and singular values.
    # One singular value is below 1e-5 and one is above it, so the expected
    # answer independently exercises the required truncation threshold.
    singular_values = [4.0, 0.2, 3e-6, 3e-5]
    b_coordinates = [1.2, -0.7, 1.1, 3e-5 * 2.3]

    while True:
        q = random_orthogonal(4)  # q[k] is column k
        a = [[sum(q[k][i] * singular_values[k] * q[k][j] for k in range(4))
              for j in range(4)] for i in range(4)]
        b = [sum(q[k][i] * b_coordinates[k] for k in range(4)) for i in range(4)]
        retained = [b_coordinates[0] / singular_values[0],
                    b_coordinates[1] / singular_values[1],
                    0.0,
                    b_coordinates[3] / singular_values[3]]
        x = [sum(q[k][i] * retained[k] for k in range(4)) for i in range(4)]

        # Avoid accidental signed zero or values near a decimal rounding tie.
        if min(abs(value) for value in x) > 0.05 and all(
            abs((abs(value) * 10000.0) % 1.0 - 0.5) > 1e-3 for value in x
        ):
            return a, b, x


def test_compiles_runs_and_uses_truncated_svd():
    assert os.path.isfile(MAIN_RS), f"File {MAIN_RS} is missing."
    with open(MAIN_RS, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "a.solve(&b)" not in content, "The buggy LU solve `a.solve(&b)` should be removed from main.rs."
    assert "svd" in content.lower(), "The code should compute the SVD of the matrix."

    with open(MATRIX, "rb") as f:
        original_matrix = f.read()
    with open(VECTOR, "rb") as f:
        original_vector = f.read()

    try:
        # Execute the submitted Rust artifact on the provided system and retain
        # the original verifier's exact expected-content assertion.
        actual = run_project()
        expected = "0.5000,-0.5000,-0.5000,0.5000"
        assert actual == expected, f"Content of {SOLUTION} is incorrect. Expected '{expected}', got '{actual}'."

        # Exercise the executable on an unpredictable case whose answer is
        # derived from a generated orthogonal factorization.
        a, b, x = make_derived_case()
        with open(MATRIX, "w") as f:
            f.write("\n".join(",".join(format(value, ".17g") for value in row) for row in a) + "\n")
        with open(VECTOR, "w") as f:
            f.write(",".join(format(value, ".17g") for value in b) + "\n")

        actual = run_project()
        expected = ",".join(f"{value:.4f}" for value in x)
        assert re.fullmatch(r"-?\d+\.\d{4}(,-?\d+\.\d{4}){3}", actual), \
            f"Solution is not a single comma-separated line with exactly four decimal places: {actual!r}"
        assert actual == expected, f"Truncated-SVD result is incorrect. Expected '{expected}', got '{actual}'."
    finally:
        with open(MATRIX, "wb") as f:
            f.write(original_matrix)
        with open(VECTOR, "wb") as f:
            f.write(original_vector)

    # Leave solution.txt corresponding to the original inputs.
    actual = run_project()
    assert actual == "0.5000,-0.5000,-0.5000,0.5000"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
