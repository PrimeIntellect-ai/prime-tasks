#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess

SOURCE = "/home/user/process_matrices.cpp"
INPUT = "/home/user/matrices.txt"
OUTPUT = "/home/user/stable_log.txt"
BINARY = "/tmp/process_matrices_verified"

CANONICAL_INPUT = """4 12 -16 12 37 -43 -16 -43 98
1 2 3 2 4 5 3 5 6
25 15 -5 15 18 0 -5 0 11
9 3 6 3 2 -2 6 -2 29
4 2 2 2 1 1 2 1 1
"""


def compute_expected_log(input_file):
    expected_lines = []
    with open(input_file, "r") as f:
        for line in f:
            if not line.strip():
                continue
            vals = list(map(float, line.split()))
            if len(vals) != 9:
                continue
            A = [vals[0:3], vals[3:6], vals[6:9]]
            L = [[0.0] * 3 for _ in range(3)]
            stable = True
            for i in range(3):
                for j in range(i + 1):
                    s = A[i][j]
                    for k in range(j):
                        s -= L[i][k] * L[j][k]
                    if i == j:
                        if s <= 1e-6:
                            stable = False
                            break
                        L[i][j] = math.sqrt(s)
                    else:
                        L[i][j] = s / L[j][j]
                if not stable:
                    break

            if stable:
                l_sum = sum(sum(row) for row in L)
                expected_lines.append(f"Stable: {l_sum:.2f}")
            else:
                expected_lines.append("Unstable")
    return expected_lines


def assert_regular_file(path, message):
    assert os.path.exists(path), message
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular file."


def matrix_from_lower(L):
    A = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            A[i][j] = sum(L[i][k] * L[j][k] for k in range(3))
    return A


def format_matrices(matrices):
    lines = []
    for A in matrices:
        lines.append(" ".join(format(A[i][j], ".17g") for i in range(3) for j in range(3)))
    return "\n".join(lines) + "\n"


def make_random_batch():
    rng = secrets.SystemRandom()
    matrices = []

    for _ in range(7):
        L = [
            [rng.randint(80, 430) / 113.0, 0.0, 0.0],
            [rng.randint(-300, 300) / 137.0, rng.randint(70, 390) / 127.0, 0.0],
            [rng.randint(-300, 300) / 149.0, rng.randint(-300, 300) / 139.0, rng.randint(60, 350) / 131.0],
        ]
        matrices.append(matrix_from_lower(L))

    matrices.append([[1e-7, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 3.0]])
    matrices.append([[2.0, 0.0, 0.0], [0.0, 1e-6, 0.0], [0.0, 0.0, 4.0]])
    matrices.append([[1.0, 2.0, 0.0], [2.0, 1.0, 0.0], [0.0, 0.0, 1.0]])

    L = [[2.3, 0.0, 0.0], [-1.1, 1.7, 0.0], [0.8, -0.6, 1.4]]
    almost = matrix_from_lower(L)
    almost[2][2] -= L[2][2] * L[2][2] - 5e-7
    matrices.append(almost)

    rng.shuffle(matrices)
    return format_matrices(matrices)


def run_and_check(input_text):
    with open(INPUT, "w") as f:
        f.write(input_text)

    # Freeze the expected result before executing the untrusted artifact, so the
    # program cannot obtain a vacuous pass by truncating or rewriting its input.
    expected_lines = compute_expected_log(INPUT)
    assert expected_lines, "Verifier test input unexpectedly produced no cases."

    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=10)

    assert_regular_file(OUTPUT, "/home/user/stable_log.txt does not exist.")
    with open(OUTPUT, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in stable_log.txt, but got {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i + 1} mismatch: expected '{expected}', got '{actual}'."
        )


def test_program_and_stable_log():
    assert_regular_file(SOURCE, "/home/user/process_matrices.cpp does not exist.")
    assert_regular_file(INPUT, f"{INPUT} is missing, cannot verify.")
    assert_regular_file(OUTPUT, "/home/user/stable_log.txt does not exist.")

    subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
        check=True,
        timeout=30,
    )
    assert_regular_file(BINARY, "Compiled program was not created.")

    run_and_check(CANONICAL_INPUT)
    run_and_check(make_random_batch())
    run_and_check(make_random_batch())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
