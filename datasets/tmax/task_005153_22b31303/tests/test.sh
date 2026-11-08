#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

WORKSPACE_DIR = "/home/user/workspace"
RESULT_FILE = os.path.join(WORKSPACE_DIR, "result.txt")
COV_MATRIX_FILE = os.path.join(WORKSPACE_DIR, "cov_matrix.txt")
Z_SAMPLES_FILE = os.path.join(WORKSPACE_DIR, "z_samples.txt")

def cholesky(matrix):
    n = len(matrix)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                val = matrix[i][i] - s
                L[i][j] = math.sqrt(max(0.0, val))
            else:
                L[i][j] = (1.0 / L[j][j] * (matrix[i][j] - s)) if L[j][j] != 0 else 0
    return L

def test_result_file_exists():
    assert os.path.isfile(RESULT_FILE), f"The result file was not found at {RESULT_FILE}."

def test_result_value():
    # Read cov matrix
    cov_matrix = []
    with open(COV_MATRIX_FILE, 'r') as f:
        for line in f:
            cov_matrix.append([float(x) for x in line.strip().split()])

    # Regularize
    for i in range(3):
        cov_matrix[i][i] += 1e-5

    L = cholesky(cov_matrix)
    mu = [0.5, 1.0, 2.0]

    # Read z samples
    z_samples = []
    with open(Z_SAMPLES_FILE, 'r') as f:
        for line in f:
            z_samples.append([float(x) for x in line.strip().split()])

    dt = 0.01
    steps = 200

    final_ys = []
    for z in z_samples:
        theta = [
            mu[0] + L[0][0]*z[0] + L[0][1]*z[1] + L[0][2]*z[2],
            mu[1] + L[1][0]*z[0] + L[1][1]*z[1] + L[1][2]*z[2],
            mu[2] + L[2][0]*z[0] + L[2][1]*z[1] + L[2][2]*z[2]
        ]

        y = 5.0
        for i in range(steps):
            t = i * dt
            dy = -theta[0] * y + theta[1] * math.sin(theta[2] * t)
            y += dy * dt
        final_ys.append(y)

    expected_avg = sum(final_ys) / len(final_ys)

    with open(RESULT_FILE, 'r') as f:
        result_str = f.read().strip()

    try:
        actual_avg = float(result_str)
    except ValueError:
        assert False, f"Result file does not contain a valid float: {result_str}"

    assert abs(actual_avg - expected_avg) <= 0.0005, f"Expected average around {expected_avg:.4f}, but got {actual_avg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
