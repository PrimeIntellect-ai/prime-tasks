#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
import pytest

def invert_3x3(m):
    # m is a list of lists: 3x3
    det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
           m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
           m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))

    inv = [
        [
            (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det,
            (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det,
            (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det
        ],
        [
            (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det,
            (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det,
            (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det
        ],
        [
            (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det,
            (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det,
            (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det
        ]
    ]
    return inv

def mat_mul(A, B):
    # A is n x m, B is m x p
    n = len(A)
    m = len(A[0])
    p = len(B[0]) if isinstance(B[0], list) else 1

    if isinstance(B[0], list):
        res = [[0] * p for _ in range(n)]
        for i in range(n):
            for j in range(p):
                res[i][j] = sum(A[i][k] * B[k][j] for k in range(m))
        return res
    else:
        res = [0] * n
        for i in range(n):
            res[i] = sum(A[i][k] * B[k] for k in range(m))
        return res

def transpose(A):
    return [[A[j][i] for j in range(len(A))] for i in range(len(A[0]))]

def compute_expected_results():
    csv_path = "/home/user/sensor_data.csv"
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    sensor1 = [float(r['sensor1']) for r in rows]
    sensor2 = [float(r['sensor2']) if r['sensor2'] != 'NaN' else None for r in rows]
    target = [float(r['target']) for r in rows]

    n = len(sensor1)
    mean1 = sum(sensor1) / n
    std1 = math.sqrt(sum((x - mean1)**2 for x in sensor1) / n)

    valid_indices = []
    outliers_removed = 0
    for i in range(n):
        if abs(sensor1[i] - mean1) / std1 > 3.0:
            outliers_removed += 1
        else:
            valid_indices.append(i)

    filtered_s2 = [sensor2[i] for i in valid_indices if sensor2[i] is not None]
    imputed_mean = sum(filtered_s2) / len(filtered_s2)

    X = []
    y = []
    for i in valid_indices:
        s1 = sensor1[i]
        s2 = sensor2[i] if sensor2[i] is not None else imputed_mean
        X.append([1.0, s1, s2])
        y.append(target[i])

    n_clean = len(X)
    fold_size = n_clean // 5

    alphas = [0.1, 1.0, 10.0]
    best_alpha = None
    best_mse = float('inf')

    for alpha in alphas:
        mse_sum = 0
        for fold in range(5):
            val_start = fold * fold_size
            val_end = val_start + fold_size

            X_train = X[:val_start] + X[val_end:]
            y_train = y[:val_start] + y[val_end:]

            X_val = X[val_start:val_end]
            y_val = y[val_start:val_end]

            Xt = transpose(X_train)
            XtX = mat_mul(Xt, X_train)

            for i in range(3):
                XtX[i][i] += alpha

            XtX_inv = invert_3x3(XtX)
            Xty = mat_mul(Xt, y_train)
            w = mat_mul(XtX_inv, Xty)

            fold_mse = 0
            for i in range(len(X_val)):
                pred = sum(X_val[i][j] * w[j] for j in range(3))
                fold_mse += (pred - y_val[i])**2
            fold_mse /= len(X_val)
            mse_sum += fold_mse

        avg_mse = mse_sum / 5
        if avg_mse < best_mse:
            best_mse = avg_mse
            best_alpha = alpha

    return {
        "outliers_removed": outliers_removed,
        "imputed_mean": imputed_mean,
        "best_alpha": best_alpha,
        "cv_mse_best_alpha": best_mse
    }

def test_pipeline_results_exists():
    """Ensure the output file is generated."""
    file_path = "/home/user/pipeline_results.json"
    assert os.path.exists(file_path), f"Output file {file_path} was not created."

def test_pipeline_results_content():
    """Verify the JSON content matches the expected values."""
    file_path = "/home/user/pipeline_results.json"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected = compute_expected_results()

    assert "outliers_removed" in results, "Missing 'outliers_removed' in JSON."
    assert results["outliers_removed"] == expected["outliers_removed"], \
        f"Expected {expected['outliers_removed']} outliers removed, got {results['outliers_removed']}."

    assert "imputed_mean" in results, "Missing 'imputed_mean' in JSON."
    assert abs(results["imputed_mean"] - expected["imputed_mean"]) < 1e-3, \
        f"Expected imputed_mean ~{expected['imputed_mean']:.4f}, got {results['imputed_mean']}."

    assert "best_alpha" in results, "Missing 'best_alpha' in JSON."
    assert abs(results["best_alpha"] - expected["best_alpha"]) < 1e-3, \
        f"Expected best_alpha ~{expected['best_alpha']:.4f}, got {results['best_alpha']}."

    assert "cv_mse_best_alpha" in results, "Missing 'cv_mse_best_alpha' in JSON."
    assert abs(results["cv_mse_best_alpha"] - expected["cv_mse_best_alpha"]) < 1e-3, \
        f"Expected cv_mse_best_alpha ~{expected['cv_mse_best_alpha']:.4f}, got {results['cv_mse_best_alpha']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
