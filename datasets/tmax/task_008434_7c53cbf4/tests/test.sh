#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def dot_product(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))

def mat_mul(A, B):
    B_T = list(zip(*B))
    return [[dot_product(row, col) for col in B_T] for row in A]

def vec_add(v1, v2):
    return [x + y for x, y in zip(v1, v2)]

def relu(v):
    return [max(0.0, x) for x in v]

def l2_norm(v):
    return math.sqrt(sum(x * x for x in v))

def test_predictions_correct():
    predictions_file = "/home/user/predictions.txt"
    assert os.path.exists(predictions_file), f"Output file missing: {predictions_file}"

    # 1. Data Cleaning
    raw_features_file = "/home/user/data/raw_features.csv"
    with open(raw_features_file, 'r') as f:
        raw_lines = f.read().strip().split('\n')

    valid_X = []
    for line in raw_lines:
        if "CORRUPT" in line:
            continue
        parts = line.split(',')
        if len(parts) != 10:
            continue
        try:
            row = [float(x) for x in parts]
            valid_X.append(row)
        except ValueError:
            pass

    # 2. Load Projection Matrix
    projection_file = "/home/user/data/projection.csv"
    with open(projection_file, 'r') as f:
        P = [[float(x) for x in line.split(',')] for line in f.read().strip().split('\n')]

    # 3. Load Weights
    weights_file = "/home/user/data/weights.json"
    with open(weights_file, 'r') as f:
        weights = json.load(f)

    W1 = weights['W1']
    b1 = weights['b1']
    W2 = weights['W2']
    b2 = weights['b2']

    # 4. Feature Engineering
    X_proj = mat_mul(valid_X, P)
    X_norm = []
    for row in X_proj:
        norm = l2_norm(row)
        X_norm.append([x / norm for x in row])

    # 5. Model Architecture Reconstruction and Inference
    H_pre = mat_mul(X_norm, W1)
    H = [relu(vec_add(row, b1)) for row in H_pre]

    Y_pre = mat_mul(H, W2)
    Y = [vec_add(row, b2) for row in Y_pre]

    # 6. Reporting
    expected_preds = []
    for row in Y:
        max_val = max(row)
        expected_preds.append(row.index(max_val))

    # Read actual predictions
    with open(predictions_file, 'r') as f:
        actual_lines = f.read().strip().split('\n')

    actual_preds = []
    for i, line in enumerate(actual_lines):
        try:
            actual_preds.append(int(line.strip()))
        except ValueError:
            pytest.fail(f"Invalid integer on line {i+1} of {predictions_file}: '{line}'")

    assert len(actual_preds) == len(expected_preds), f"Expected {len(expected_preds)} predictions, got {len(actual_preds)}."

    mismatches = 0
    for i, (actual, expected) in enumerate(zip(actual_preds, expected_preds)):
        if actual != expected:
            mismatches += 1
            if mismatches <= 5:
                print(f"Mismatch at index {i}: expected {expected}, got {actual}")

    assert mismatches == 0, f"Found {mismatches} mismatched predictions."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
