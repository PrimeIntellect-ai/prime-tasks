#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv

def solve_ols(X, Y):
    """Simple Ordinary Least Squares solver using Gaussian elimination."""
    n = len(X)
    k = len(X[0])

    # Compute X^T X and X^T Y
    XtX = [[0.0] * k for _ in range(k)]
    XtY = [0.0] * k
    for i in range(n):
        for j in range(k):
            XtY[j] += X[i][j] * Y[i]
            for m in range(k):
                XtX[j][m] += X[i][j] * X[i][m]

    # Augmented matrix for Gaussian elimination
    A = [XtX[i] + [XtY[i]] for i in range(k)]

    for i in range(k):
        # Find pivot
        max_row = i
        for j in range(i + 1, k):
            if abs(A[j][i]) > abs(A[max_row][i]):
                max_row = j
        A[i], A[max_row] = A[max_row], A[i]

        pivot = A[i][i]
        if pivot == 0:
            raise ValueError("Matrix is singular")

        for j in range(i, k + 1):
            A[i][j] /= pivot

        for j in range(k):
            if i != j:
                factor = A[j][i]
                for m in range(i, k + 1):
                    A[j][m] -= factor * A[i][m]

    return [A[i][k] for i in range(k)]

def test_model_params_json():
    csv_path = "/home/user/perf_logs.csv"
    json_path = "/home/user/model_params.json"

    assert os.path.exists(json_path), f"Output file {json_path} does not exist."

    # Read and parse CSV
    X_data = []
    Y_data = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            c = float(row['concurrency'])
            d = float(row['data_size_kb'])
            l = float(row['latency_ms'])
            if l <= 9000:
                X_data.append([c, d, c * d, 1.0])
                Y_data.append(l)

    # Compute true parameters
    params = solve_ols(X_data, Y_data)
    truth = {
        "a": round(params[0], 4),
        "b": round(params[1], 4),
        "c": round(params[2], 4),
        "d": round(params[3], 4)
    }

    # Read agent output
    with open(json_path, 'r') as f:
        try:
            agent_output = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    # Verify exact keys
    expected_keys = {"a", "b", "c", "d"}
    assert set(agent_output.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}. Got {list(agent_output.keys())}."

    # Verify values
    for key in expected_keys:
        expected_val = truth[key]
        agent_val = agent_output[key]
        assert isinstance(agent_val, (int, float)), f"Value for '{key}' must be a number."
        assert abs(agent_val - expected_val) <= 0.0001, f"Mismatch for parameter '{key}': expected {expected_val}, got {agent_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
