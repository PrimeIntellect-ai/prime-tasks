#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import pytest

def test_clean_data_and_lambda():
    dataset_path = "/home/user/dataset.csv"
    clean_data_path = "/home/user/clean_data.csv"
    best_lambda_path = "/home/user/best_lambda.txt"

    assert os.path.isfile(dataset_path), f"Original dataset missing at {dataset_path}"
    assert os.path.isfile(clean_data_path), f"Cleaned dataset missing at {clean_data_path}"
    assert os.path.isfile(best_lambda_path), f"Best lambda file missing at {best_lambda_path}"

    # 1. Read original data and compute means
    f1_vals = []
    f2_vals = []
    raw_data = []

    with open(dataset_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append(row)
            if row['f1'] != 'NaN':
                f1_vals.append(float(row['f1']))
            if row['f2'] != 'NaN':
                f2_vals.append(float(row['f2']))

    f1_mean = sum(f1_vals) / len(f1_vals)
    f2_mean = sum(f2_vals) / len(f2_vals)

    # 2. Impute and format
    expected_clean_data = []
    imputed_data = []
    for row in raw_data:
        id_val = row['id']

        f1_val = float(row['f1']) if row['f1'] != 'NaN' else f1_mean
        f2_val = float(row['f2']) if row['f2'] != 'NaN' else f2_mean
        y_val = float(row['y'])

        imputed_data.append({'f1': f1_val, 'f2': f2_val, 'y': y_val})

        expected_clean_data.append([
            id_val,
            f"{f1_val:.4f}",
            f"{f2_val:.4f}",
            f"{y_val:.4f}"
        ])

    # 3. Verify clean_data.csv
    with open(clean_data_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'f1', 'f2', 'y'], "Header in clean_data.csv is incorrect"

        actual_clean_data = list(reader)

        assert len(actual_clean_data) == len(expected_clean_data), "Row count mismatch in clean_data.csv"

        for i, (actual, expected) in enumerate(zip(actual_clean_data, expected_clean_data)):
            assert actual == expected, f"Data mismatch at row {i+1}. Expected {expected}, got {actual}"

    # 4. Compute best lambda
    lambdas = [0.1, 1.0, 10.0]
    best_l = None
    best_mse = float('inf')

    n_rows = len(imputed_data)
    fold_size = n_rows // 5

    for l in lambdas:
        mse_total = 0
        for fold in range(5):
            val_idx = set(range(fold * fold_size, (fold + 1) * fold_size))

            X_train = []
            Y_train = []
            X_val = []
            Y_val = []

            for i, row in enumerate(imputed_data):
                if i in val_idx:
                    X_val.append([row['f1'], row['f2']])
                    Y_val.append(row['y'])
                else:
                    X_train.append([row['f1'], row['f2']])
                    Y_train.append(row['y'])

            # X^T X + l*I
            a = sum(x[0]*x[0] for x in X_train) + l
            b = sum(x[0]*x[1] for x in X_train)
            c = sum(x[1]*x[0] for x in X_train)
            d = sum(x[1]*x[1] for x in X_train) + l

            # X^T Y
            xty0 = sum(x[0]*y for x, y in zip(X_train, Y_train))
            xty1 = sum(x[1]*y for x, y in zip(X_train, Y_train))

            # Inverse of 2x2 matrix
            det = a*d - b*c
            inv_a = d / det
            inv_b = -b / det
            inv_c = -c / det
            inv_d = a / det

            # Beta
            beta0 = inv_a * xty0 + inv_b * xty1
            beta1 = inv_c * xty0 + inv_d * xty1

            # MSE
            mse = 0
            for x, y in zip(X_val, Y_val):
                pred = x[0]*beta0 + x[1]*beta1
                mse += (y - pred)**2
            mse /= len(X_val)

            mse_total += mse

        avg_mse = mse_total / 5
        if avg_mse < best_mse:
            best_mse = avg_mse
            best_l = l

    # 5. Verify best_lambda.txt
    with open(best_lambda_path, 'r') as f:
        actual_l_str = f.read().strip()
        try:
            actual_l = float(actual_l_str)
        except ValueError:
            pytest.fail(f"best_lambda.txt does not contain a valid float: {actual_l_str}")

    assert math.isclose(actual_l, best_l, rel_tol=1e-5), f"Expected best lambda {best_l}, got {actual_l}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
