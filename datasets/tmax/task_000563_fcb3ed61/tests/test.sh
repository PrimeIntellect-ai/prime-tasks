#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def compute_expected_r2(csv_path):
    """
    Computes the expected R^2 score using pure Python standard library.
    Follows the exact pipeline:
    1. Schema enforcement (drop non-numeric/NaN)
    2. StandardScaler (population std dev)
    3. PCA (1 component via Power Iteration)
    4. Linear Regression
    5. R^2 score calculation
    """
    if not os.path.exists(csv_path):
        return None

    data = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                s1 = float(row['s1'])
                s2 = float(row['s2'])
                s3 = float(row['s3'])
                s4 = float(row['s4'])
                s5 = float(row['s5'])
                target = float(row['target'])
                if any(math.isnan(x) for x in [s1, s2, s3, s4, s5, target]):
                    continue
                data.append([s1, s2, s3, s4, s5, target])
            except ValueError:
                continue

    if not data:
        return None

    N = len(data)
    X = [[row[i] for i in range(5)] for row in data]
    y = [row[5] for row in data]

    # StandardScaler (uses N for variance, as in sklearn)
    means = [sum(col) / N for col in zip(*X)]
    stds = [math.sqrt(sum((val - m)**2 for val in col) / N) for col, m in zip(zip(*X), means)]

    X_scaled = [[(row[i] - means[i]) / stds[i] for i in range(5)] for row in X]

    # Covariance matrix (proportional to X_scaled^T X_scaled)
    cov = [[sum(X_scaled[k][i] * X_scaled[k][j] for k in range(N)) for j in range(5)] for i in range(5)]

    # Power iteration to find the first principal component
    v = [1.0] * 5
    for _ in range(200):
        v_new = [sum(cov[i][j] * v[j] for j in range(5)) for i in range(5)]
        norm = math.sqrt(sum(x**2 for x in v_new))
        v = [x / norm for x in v_new]

    # Project data onto the first principal component
    PC1 = [sum(X_scaled[k][i] * v[i] for i in range(5)) for k in range(N)]

    # Linear Regression of y on PC1
    mean_pc1 = sum(PC1) / N
    mean_y = sum(y) / N

    cov_pc1_y = sum((PC1[i] - mean_pc1) * (y[i] - mean_y) for i in range(N))
    var_pc1 = sum((PC1[i] - mean_pc1)**2 for i in range(N))

    if var_pc1 == 0:
        return None

    slope = cov_pc1_y / var_pc1
    intercept = mean_y - slope * mean_pc1

    y_pred = [slope * x + intercept for x in PC1]

    # Calculate R^2 score
    ss_res = sum((y[i] - y_pred[i])**2 for i in range(N))
    ss_tot = sum((y[i] - mean_y)**2 for i in range(N))

    r2 = 1 - (ss_res / ss_tot)
    return f"{r2:.4f}"

def test_metrics_file_exists_and_correct():
    metrics_path = "/home/user/metrics.txt"
    csv_path = "/home/user/sensor_data.csv"

    assert os.path.isfile(metrics_path), f"The file {metrics_path} does not exist."

    with open(metrics_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_r2 = compute_expected_r2(csv_path)
    assert expected_r2 is not None, "Could not compute expected R^2 score from the dataset."

    assert content == expected_r2, (
        f"The R^2 score in {metrics_path} is incorrect. "
        f"Expected '{expected_r2}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
