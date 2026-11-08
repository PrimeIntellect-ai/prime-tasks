#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import subprocess
import pytest

SCRIPT_PATH = '/home/user/bayesian_model.py'
RESULTS_PATH = '/home/user/results.json'
DATA_PATH = '/home/user/data.csv'

def transpose(A):
    return [list(col) for col in zip(*A)]

def matmul(A, B):
    if isinstance(B[0], (int, float)):
        return [sum(a * b for a, b in zip(row, B)) for row in A]
    return [[sum(a * b for a, b in zip(row_A, col_B)) for col_B in zip(*B)] for row_A in A]

def add_mat(A, B):
    return [[a + b for a, b in zip(row_A, row_B)] for row_A, row_B in zip(A, B)]

def scale_mat(A, scalar):
    return [[a * scalar for a in row] for row in A]

def invert_2x2(A):
    det = A[0][0] * A[1][1] - A[0][1] * A[1][0]
    return [[A[1][1] / det, -A[0][1] / det], [-A[1][0] / det, A[0][0] / det]]

def get_mean_std(X):
    n = len(X)
    means = [sum(col) / n for col in zip(*X)]
    stds = [math.sqrt(sum((x - m)**2 for x in col) / n) for col, m in zip(zip(*X), means)]
    return means, stds

def scale_data(X, means, stds):
    return [[(x - m) / s for x, m, s in zip(row, means, stds)] for row in X]

def get_cov(X):
    n = len(X)
    means = [sum(col) / n for col in zip(*X)]
    cov = [[0.0, 0.0], [0.0, 0.0]]
    for i in range(2):
        for j in range(2):
            cov[i][j] = sum((X[k][i] - means[i]) * (X[k][j] - means[j]) for k in range(n)) / (n - 1)
    return cov

def get_expected_results():
    if not os.path.exists(DATA_PATH):
        pytest.fail(f'Data file missing: {DATA_PATH}')

    with open(DATA_PATH, 'r') as f:
        data = list(csv.DictReader(f))

    X = [[float(row['X1']), float(row['X2'])] for row in data]
    y = [float(row['y']) for row in data]
    X_train_raw, X_test_raw = X[:80], X[80:]
    y_train = y[:80]

    means, stds = get_mean_std(X_train_raw)
    X_train = scale_data(X_train_raw, means, stds)
    X_test = scale_data(X_test_raw, means, stds)

    expected_cov = [[round(c, 4) for c in row] for row in get_cov(X_train)]

    sigma_noise_sq = 0.25
    alpha = 1.0
    X_train_T = transpose(X_train)
    XtX = matmul(X_train_T, X_train)
    I_alpha = [[1.0 / alpha, 0.0], [0.0, 1.0 / alpha]]
    V_N_inv = add_mat(I_alpha, scale_mat(XtX, 1.0 / sigma_noise_sq))
    V_N = invert_2x2(V_N_inv)
    Xty_sigma = [val / sigma_noise_sq for val in matmul(X_train_T, y_train)]
    w_N = matmul(V_N, Xty_sigma)
    expected_y_pred = [round(val, 4) for val in matmul(X_test, w_N)]
    return expected_cov, expected_y_pred

def test_script_generates_results():
    assert os.path.isfile(SCRIPT_PATH), f'Script missing: {SCRIPT_PATH}'

    # The required artifact itself must produce the deliverable; a precomputed JSON
    # made by some other command must not be sufficient.
    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    try:
        completed = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('bayesian_model.py timed out')

    assert completed.returncode == 0, (
        'bayesian_model.py failed with exit code '
        f'{completed.returncode}. stderr: {completed.stderr}'
    )
    assert os.path.isfile(RESULTS_PATH), (
        'bayesian_model.py did not create /home/user/results.json'
    )

    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('results.json is not a valid JSON file.')

    assert 'train_feature_covariance' in results, "Missing key 'train_feature_covariance' in results.json"
    assert 'test_predictions' in results, "Missing key 'test_predictions' in results.json"

    expected_cov, expected_y_pred = get_expected_results()
    actual_cov = results['train_feature_covariance']
    actual_y_pred = results['test_predictions']

    assert len(actual_cov) == 2 and len(actual_cov[0]) == 2 and len(actual_cov[1]) == 2, \
        'train_feature_covariance must be a 2x2 matrix'
    for i in range(2):
        for j in range(2):
            assert math.isclose(actual_cov[i][j], expected_cov[i][j], abs_tol=1e-4), \
                f'Covariance mismatch at [{i}][{j}]. Expected {expected_cov[i][j]}, got {actual_cov[i][j]}'

    assert len(actual_y_pred) == 20, f'Expected 20 test predictions, got {len(actual_y_pred)}'
    for i, (actual, expected) in enumerate(zip(actual_y_pred, expected_y_pred)):
        assert math.isclose(actual, expected, abs_tol=1e-4), \
            f'Prediction mismatch at index {i}. Expected {expected}, got {actual}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
