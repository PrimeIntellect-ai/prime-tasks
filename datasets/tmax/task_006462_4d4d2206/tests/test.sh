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

SOURCE = "/home/user/analyze_gc.c"
SYSTEM = "/home/user/system.txt"
DATA = "/home/user/gc_data.txt"
RESULT = "/home/user/lrt_result.txt"
EXE = "/tmp/analyze_gc_verified"

BASE_MATRIX = [
    [4.0, 1.0, 1.0, 9.0],
    [1.0, 3.0, 0.0, 7.0],
    [0.0, 1.0, 2.0, 8.0],
]
BASE_DATA = [0.80, 0.90, 0.95]


def write_inputs(matrix, points):
    with open(SYSTEM, "w") as f:
        for row in matrix:
            f.write(" ".join(format(v, ".17g") for v in row) + "\n")
    with open(DATA, "w") as f:
        for x in points:
            f.write(format(x, ".17g") + "\n")


def solve(matrix):
    a = [row[:] for row in matrix]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(a[r][col]))
        assert abs(a[pivot][col]) > 1e-12
        a[col], a[pivot] = a[pivot], a[col]
        for row in range(col + 1, 3):
            factor = a[row][col] / a[col][col]
            for j in range(col, 4):
                a[row][j] -= factor * a[col][j]
    c = [0.0, 0.0, 0.0]
    for row in range(2, -1, -1):
        c[row] = (a[row][3] - sum(a[row][j] * c[j] for j in range(row + 1, 3))) / a[row][row]
    return c


def expected_result(matrix, points):
    c0, c1, c2 = solve(matrix)

    # Independently perform the required Simpson 1/3 calculation at 101 points.
    h = 1.0 / 100.0
    total = 0.0
    for i in range(101):
        x = i * h
        fx = c0 + c1 * x + c2 * x * x
        if i == 0 or i == 100:
            weight = 1.0
        elif i % 2:
            weight = 4.0
        else:
            weight = 2.0
        total += weight * fx
    z = total * h / 3.0

    ll_alt = 0.0
    for x in points:
        p = (c0 + c1 * x + c2 * x * x) / z
        assert p > 0.0 and math.isfinite(p)
        ll_alt += math.log(p)
    return f"{2.0 * ll_alt:.5f}"


def run_and_check(matrix, points):
    write_inputs(matrix, points)
    if os.path.exists(RESULT):
        os.remove(RESULT)
    proc = subprocess.run([EXE], cwd="/home/user", capture_output=True, text=True, timeout=5)
    assert proc.returncode == 0, f"Program exited with status {proc.returncode}: {proc.stderr}"
    assert os.path.isfile(RESULT), f"The output file {RESULT} is missing. Did your program run successfully?"
    with open(RESULT, "r") as f:
        raw = f.read()
    assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)\.[0-9]{5}\n?", raw), \
        "lrt_result.txt must contain only one decimal value with exactly five places"
    content = raw.strip()
    expected = expected_result(matrix, points)
    assert content == expected, f"Content of {RESULT} is incorrect. Expected '{expected}', got '{content}'."


@pytest.fixture(scope="session", autouse=True)
def compile_submission():
    assert os.path.isfile(SOURCE), f"The C program {SOURCE} is missing. You must write the program."
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert source.strip(), "analyze_gc.c is empty"
    # Basic source evidence for the mandated 100-subinterval iterative integration.
    assert re.search(r"\b100\b", source), "Source does not specify the required N=100 Simpson integration"
    assert re.search(r"\b(for|while)\b", source), "Source does not contain an iterative numerical integration"
    proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", EXE],
        capture_output=True, text=True, timeout=20
    )
    assert proc.returncode == 0, f"analyze_gc.c did not compile:\n{proc.stdout}{proc.stderr}"
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK)


def test_c_program_exists():
    assert os.path.isfile(SOURCE), f"The C program {SOURCE} is missing. You must write the program."


def test_lrt_result_exists_and_correct():
    # Restore and execute against the task's original inputs; do not trust a fabricated result.
    run_and_check(BASE_MATRIX, BASE_DATA)


def test_program_solves_and_analyzes_unseen_inputs():
    rng = random.SystemRandom()
    try:
        for _ in range(6):
            # Strictly diagonally dominant matrices are nonsingular, while randomized
            # off-diagonal terms prevent hard-coding the original coefficients.
            m = [
                [rng.randint(6, 10), rng.randint(-2, 2), rng.randint(-2, 2)],
                [rng.randint(-2, 2), rng.randint(6, 10), rng.randint(-2, 2)],
                [rng.randint(-2, 2), rng.randint(-2, 2), rng.randint(6, 10)],
            ]
            coefficients = [rng.randint(5, 20) / 10.0 for _ in range(3)]
            augmented = []
            for row in m:
                y = sum(row[j] * coefficients[j] for j in range(3))
                augmented.append([float(row[0]), float(row[1]), float(row[2]), y])
            points = [rng.randint(1, 99) / 100.0 for _ in range(rng.randint(4, 10))]
            run_and_check(augmented, points)
    finally:
        # Leave the requested artifact corresponding to the original task inputs.
        write_inputs(BASE_MATRIX, BASE_DATA)
        if os.path.isfile(EXE):
            subprocess.run([EXE], cwd="/home/user", capture_output=True, timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
