#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess
import tempfile

INPUT_FILE = "/home/user/protein_features.csv"
OUTPUT_FILE = "/home/user/weights.csv"
SOURCE_FILE = "/home/user/solve_weights.cpp"


def solve_linear_system(A, b):
    n = len(b)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]

    for i in range(n):
        max_row = max(range(i, n), key=lambda r: abs(M[r][i]))
        M[i], M[max_row] = M[max_row], M[i]
        assert abs(M[i][i]) > 1e-14

        for j in range(i + 1, n):
            factor = M[j][i] / M[i][i]
            for k in range(i, n + 1):
                M[j][k] -= factor * M[i][k]

    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        x[i] = M[i][n] / M[i][i]
        for j in range(i - 1, -1, -1):
            M[j][n] -= M[j][i] * x[i]

    return x


def expected_weights(rows):
    X = [row[:3] for row in rows]
    y = [row[3] for row in rows]

    A = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            A[i][j] = sum(X[k][i] * X[k][j] for k in range(len(X)))

    for i in range(3):
        A[i][i] += 0.05

    b = [0.0] * 3
    for i in range(3):
        b[i] = sum(X[k][i] * y[k] for k in range(len(X)))

    return solve_linear_system(A, b)


def read_rows(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = [float(p.strip()) for p in line.split(",")]
            assert len(parts) == 4, f"Expected four values per input row, got {len(parts)}"
            rows.append(parts)
    return rows


def check_output(expected):
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    assert content, f"Output file {OUTPUT_FILE} is empty."
    lines = content.split('\n')
    assert len(lines) == 1, f"Expected exactly 1 line in {OUTPUT_FILE}, found {len(lines)}."

    parts = lines[0].split(',')
    assert len(parts) == 3, f"Expected exactly 3 comma-separated values in {OUTPUT_FILE}, found {len(parts)}."
    actual = [float(p.strip()) for p in parts]

    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isfinite(got), f"Weight w{i+1} is not finite: {got}"
        assert abs(got - want) <= 1e-3, \
            f"Weight w{i+1} mismatch: expected {want:.6f}, got {got:.6f}"


def write_rows(rows):
    with open(INPUT_FILE, "w") as f:
        for row in rows:
            f.write(", ".join(format(value, ".17g") for value in row) + "\n")


def test_weights_correctness_and_cpp_program():
    assert os.path.isfile(INPUT_FILE), f"Input file {INPUT_FILE} is missing."

    original_input = open(INPUT_FILE, "rb").read()
    output_existed = os.path.isfile(OUTPUT_FILE)
    original_output = open(OUTPUT_FILE, "rb").read() if output_existed else None
    executable = None

    try:
        # Preserve the original verifier's fixed-dataset assertions.
        assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
        original_rows = read_rows(INPUT_FILE)
        check_output(expected_weights(original_rows))

        # The requested artifact must be a real C++ source file and must compile.
        assert os.path.exists(SOURCE_FILE), f"Required source file {SOURCE_FILE} is missing."
        source_stat = os.lstat(SOURCE_FILE)
        assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_FILE} is not a regular file."
        assert not os.path.islink(SOURCE_FILE), f"{SOURCE_FILE} must not be a symbolic link."
        assert source_stat.st_size > 0, f"{SOURCE_FILE} is empty."

        fd, executable = tempfile.mkstemp(prefix="solve_weights_", dir="/tmp")
        os.close(fd)
        os.unlink(executable)
        compiled = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_FILE, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f"C++ source failed to compile:\n{compiled.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        # Exercise the compiled program on fresh, unpredictable datasets so a
        # precomputed weights.csv or hardcoded answer cannot pass.
        rng = random.SystemRandom()
        cases = []

        cases.append([[rng.uniform(-2, 2), rng.uniform(-2, 2),
                       rng.uniform(-2, 2), rng.uniform(-5, 5)]])

        cases.append([
            [rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2),
             rng.uniform(-0.2, 0.2), rng.uniform(-3, 3)]
            for _ in range(7)
        ])

        near_collinear = []
        for _ in range(9):
            x1 = rng.uniform(-3, 3)
            x2 = 2.0 * x1 + rng.uniform(-0.01, 0.01)
            x3 = -x1 + rng.uniform(-0.02, 0.02)
            y = rng.uniform(-2, 2) + 1.7 * x1 - 0.4 * x2 + 0.8 * x3
            near_collinear.append([x1, x2, x3, y])
        cases.append(near_collinear)

        cases.append([
            [rng.uniform(-4, 4), rng.uniform(-3, 3),
             rng.uniform(-2, 2), rng.uniform(-8, 8)]
            for _ in range(11)
        ])

        for index, rows in enumerate(cases):
            write_rows(rows)
            if os.path.exists(OUTPUT_FILE):
                os.unlink(OUTPUT_FILE)
            run = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert run.returncode == 0, \
                f"Compiled program failed on generated case {index}: {run.stderr}"
            check_output(expected_weights(rows))
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        if output_existed:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_FILE):
            os.unlink(OUTPUT_FILE)
        if executable and os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
