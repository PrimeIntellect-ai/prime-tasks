#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math

def transpose(M):
    return [[M[j][i] for j in range(len(M))] for i in range(len(M[0]))]

def matmul(A, B):
    B_T = transpose(B)
    return [[sum(a * b for a, b in zip(A_row, B_col)) for B_col in B_T] for A_row in A]

def minor(M, i, j):
    return [row[:j] + row[j+1:] for row in (M[:i] + M[i+1:])]

def det(M):
    if len(M) == 1:
        return M[0][0]
    if len(M) == 2:
        return M[0][0]*M[1][1] - M[0][1]*M[1][0]
    return sum(((-1)**j) * M[0][j] * det(minor(M, 0, j)) for j in range(len(M)))

def inverse(M):
    d = det(M)
    if len(M) == 1:
        return [[1.0 / d]]
    cofactors = []
    for r in range(len(M)):
        cofactor_row = []
        for c in range(len(M)):
            cofactor_row.append(((-1)**(r+c)) * det(minor(M, r, c)))
        cofactors.append(cofactor_row)
    cofactors = transpose(cofactors)
    return [[val / d for val in row] for row in cofactors]

def mean(lst):
    return sum(lst) / len(lst)

def std(lst):
    m = mean(lst)
    return math.sqrt(sum((x - m)**2 for x in lst) / (len(lst) - 1))

def pearson_corr(x, y):
    m_x = mean(x)
    m_y = mean(y)
    num = sum((a - m_x) * (b - m_y) for a, b in zip(x, y))
    den = math.sqrt(sum((a - m_x)**2 for a in x) * sum((b - m_y)**2 for b in y))
    return num / den

def test_report_json():
    csv_path = '/home/user/sensor_data.csv'
    json_path = '/home/user/report.json'

    assert os.path.exists(json_path), f"Expected {json_path} to exist."

    # Read CSV
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    features = ['sensor_A', 'sensor_B', 'sensor_C', 'sensor_D']
    data = {f: [float(r[f]) for r in rows] for f in features}
    target = [float(r['target_temp']) for r in rows]

    # Calculate correlations
    to_drop = set()
    for i in range(len(features)):
        for j in range(i+1, len(features)):
            f1, f2 = features[i], features[j]
            corr = abs(pearson_corr(data[f1], data[f2]))
            if corr > 0.90:
                if f1 > f2:
                    to_drop.add(f1)
                else:
                    to_drop.add(f2)

    expected_dropped = sorted(list(to_drop))
    expected_retained = sorted([f for f in features if f not in expected_dropped])

    # Train/test split
    train_size = int(0.8 * len(rows))

    X_train = [[1.0] + [data[f][i] for f in expected_retained] for i in range(train_size)]
    y_train = [[target[i]] for i in range(train_size)]

    X_test = [[1.0] + [data[f][i] for f in expected_retained] for i in range(train_size, len(rows))]
    y_test = target[train_size:]

    # OLS: beta = (X^T X)^-1 X^T y
    X_T = transpose(X_train)
    XTX = matmul(X_T, X_train)
    XTX_inv = inverse(XTX)
    XTy = matmul(X_T, y_train)
    beta = matmul(XTX_inv, XTy)

    # Predict and calculate RMSE
    preds = matmul(X_test, beta)
    mse = sum((preds[i][0] - y_test[i])**2 for i in range(len(y_test))) / len(y_test)
    expected_rmse = round(math.sqrt(mse), 2)

    # Validate JSON
    with open(json_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not valid JSON."

    assert "dropped_sensors" in actual, "Missing 'dropped_sensors' in report.json"
    assert "retained_sensors" in actual, "Missing 'retained_sensors' in report.json"
    assert "rmse" in actual, "Missing 'rmse' in report.json"

    assert actual["dropped_sensors"] == expected_dropped, f"Expected dropped_sensors to be {expected_dropped}, got {actual['dropped_sensors']}"
    assert actual["retained_sensors"] == expected_retained, f"Expected retained_sensors to be {expected_retained}, got {actual['retained_sensors']}"
    assert abs(actual["rmse"] - expected_rmse) <= 0.01, f"Expected rmse to be approx {expected_rmse}, got {actual['rmse']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
