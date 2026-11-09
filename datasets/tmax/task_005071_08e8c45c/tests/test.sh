#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess

import pytest

SRC_DIR = "/home/user/src"
DATA_PATH = "/home/user/data/features.csv"
OUTPUT_DIR = "/home/user/output"
OUTPUT_PATH = "/home/user/output/eigen.txt"


def read_dataset(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append([float(x) for x in line.split(",")])
    assert len(rows) >= 2, "Dataset must contain at least two rows."
    width = len(rows[0])
    assert width > 0 and all(len(row) == width for row in rows), "Dataset is not rectangular."
    return rows


def expected_eigenvalue_lines(rows):
    n = len(rows)
    d = len(rows[0])
    means = [sum(row[j] for row in rows) / n for j in range(d)]
    cov = [[0.0 for _ in range(d)] for _ in range(d)]
    for i in range(d):
        for j in range(d):
            cov[i][j] = sum(
                (row[i] - means[i]) * (row[j] - means[j]) for row in rows
            ) / (n - 1)

    # Jacobi diagonalization for the real symmetric covariance matrix.
    a = [row[:] for row in cov]
    for _ in range(100 * max(1, d * d)):
        p, q = 0, 0
        largest = 0.0
        for i in range(d):
            for j in range(i + 1, d):
                if abs(a[i][j]) > largest:
                    largest = abs(a[i][j])
                    p, q = i, j
        if largest < 1e-13:
            break

        apq = a[p][q]
        tau = (a[q][q] - a[p][p]) / (2.0 * apq)
        t = math.copysign(1.0 / (abs(tau) + math.sqrt(1.0 + tau * tau)), tau)
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c
        app, aqq = a[p][p], a[q][q]

        for k in range(d):
            if k == p or k == q:
                continue
            akp, akq = a[k][p], a[k][q]
            a[k][p] = a[p][k] = c * akp - s * akq
            a[k][q] = a[q][k] = s * akp + c * akq

        a[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq
        a[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq
        a[p][q] = a[q][p] = 0.0

    values = sorted((a[i][i] for i in range(d)), reverse=True)
    return [format(0.0 if abs(value) < 0.00005 else value, ".4f") for value in values]


def output_lines():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_output_matches(rows):
    actual = output_lines()
    expected = expected_eigenvalue_lines(rows)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines in eigen.txt, found {len(actual)}."
    )
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert re.fullmatch(r"-?\d+\.\d{4}", got), (
            f"Line {i + 1} is not formatted to exactly 4 decimal places: {got!r}."
        )
        assert got == want, f"Line {i + 1} mismatch: expected {want}, got {got}."


def run_main():
    result = subprocess.run(
        ["go", "run", "main.go"],
        cwd=SRC_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"go run main.go failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_go_mod_exists_and_correct():
    go_mod_path = "/home/user/src/go.mod"
    assert os.path.isfile(go_mod_path), f"{go_mod_path} does not exist."
    with open(go_mod_path, "r") as f:
        content = f.read()
    assert "module mle/variance" in content, (
        "The go.mod file does not contain the correct module name 'mle/variance'."
    )
    assert "gonum.org/v1/gonum" in content, (
        "The go.mod file does not contain the gonum dependency."
    )


def test_main_go_exists():
    main_go_path = "/home/user/src/main.go"
    assert os.path.isfile(main_go_path), f"{main_go_path} does not exist."


def test_eigen_txt_exists_and_correct():
    assert_output_matches(read_dataset(DATA_PATH))


def test_program_executes_and_uses_dataset():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_rows = read_dataset(DATA_PATH)

    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    generated_rows = []
    for i in range(8):
        x = rng.uniform(-8.0, 8.0) + 0.31 * i
        y = rng.uniform(-5.0, 9.0) - 0.17 * i + 0.23 * x
        z = rng.uniform(-11.0, 6.0) + 0.19 * x - 0.11 * y
        generated_rows.append([x, y, z])

    try:
        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
        run_main()
        assert_output_matches(original_rows)

        with open(DATA_PATH, "w") as f:
            for row in generated_rows:
                f.write(",".join(f"{value:.10f}" for value in row) + "\n")
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_main()
        assert_output_matches(read_dataset(DATA_PATH))
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
        run_main()

    assert_output_matches(original_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
