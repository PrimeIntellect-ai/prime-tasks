#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

SOURCE = '/home/user/process_cov.c'
CSV_FILE = '/home/user/cov_matrix.csv'
LOG_FILE = '/home/user/decomposition_results.log'
EXECUTABLE = '/tmp/process_cov_verified'


def read_csv(filepath):
    matrix = []
    with open(filepath, 'r') as f:
        for line in f:
            if line.strip():
                matrix.append([float(x) for x in line.strip().split(',')])
    return matrix


def validate_log(A):
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} missing. Did you run your C program?"
    assert os.path.exists(CSV_FILE), f"Original CSV file {CSV_FILE} missing."
    assert len(A) == 5 and all(len(row) == 5 for row in A), "Original matrix must be 5x5."

    A_reg = [[A[i][j] + (1e-4 if i == j else 0.0) for j in range(5)] for i in range(5)]

    with open(LOG_FILE, 'r') as f:
        lines = f.readlines()

    assert any("Error_Frobenius:" in line for line in lines), \
        "Log file missing 'Error_Frobenius:' line."

    l_start = -1
    for i, line in enumerate(lines):
        if line.startswith('L_Matrix:'):
            l_start = i + 1
            break

    assert l_start != -1, "Could not find 'L_Matrix:' header in the log file."
    assert len(lines) >= l_start + 5, "Log file does not contain 5 rows for the L matrix."

    L = []
    for i in range(5):
        try:
            row = [float(x.strip()) for x in lines[l_start + i].split(',')]
        except ValueError as exc:
            raise AssertionError(
                f"Could not parse floats from L matrix row {i}: {lines[l_start + i].strip()}"
            ) from exc
        assert len(row) == 5, f"Row {i} of L matrix does not have 5 elements."
        L.append(row)

    for i in range(5):
        for j in range(i + 1, 5):
            assert abs(L[i][j]) < 1e-9, \
                f"L is not lower triangular, L[{i}][{j}] = {L[i][j]} != 0"

    A_recon = [[sum(L[i][k] * L[j][k] for k in range(5))
                for j in range(5)] for i in range(5)]

    error_sq = 0.0
    for i in range(5):
        for j in range(5):
            diff = A_recon[i][j] - A_reg[i][j]
            error_sq += diff * diff

    error = math.sqrt(error_sq)
    assert error <= 1e-4, \
        f"Reconstruction error too high: {error} > 1e-4. The decomposition does not match the regularized matrix."


def write_matrix(A):
    with open(CSV_FILE, 'w') as f:
        for row in A:
            f.write(','.join(f'{value:.12f}' for value in row) + '\n')


def random_rank_four_covariance(rng):
    base = [[rng.uniform(-2.0, 2.0) for _ in range(4)] for _ in range(5)]
    return [[sum(base[i][k] * base[j][k] for k in range(4))
             for j in range(5)] for i in range(5)]


def run_and_validate(A):
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    completed = subprocess.run(
        [EXECUTABLE], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, \
        f"Compiled C program exited with status {completed.returncode}: {completed.stderr}"
    validate_log(A)


def main():
    assert os.path.exists(SOURCE), f"Required C source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), \
        f"{SOURCE} must be a regular C source file."
    assert os.path.getsize(SOURCE) > 0, f"C source file {SOURCE} is empty."
    assert os.path.exists(CSV_FILE), f"Original CSV file {CSV_FILE} missing."

    with open(CSV_FILE, 'rb') as f:
        original_csv = f.read()
    original_A = read_csv(CSV_FILE)

    compile_result = subprocess.run(
        ['gcc', '-O2', '-o', EXECUTABLE, SOURCE, '-lm'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, \
        f"Failed to compile {SOURCE} with GCC: {compile_result.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        "GCC did not produce an executable program."

    rng = random.SystemRandom()
    try:
        for _ in range(3):
            challenge = random_rank_four_covariance(rng)
            write_matrix(challenge)
            run_and_validate(challenge)

        with open(CSV_FILE, 'wb') as f:
            f.write(original_csv)
        run_and_validate(original_A)
    finally:
        with open(CSV_FILE, 'wb') as f:
            f.write(original_csv)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
