#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def test_mse_result():
    train_file = "/home/user/train.csv"
    test_file = "/home/user/test.csv"
    labels_file = "/home/user/labels.csv"
    result_file = "/home/user/mse_result.txt"

    assert os.path.exists(result_file), f"Output file {result_file} does not exist. The task requires saving the result here."

    # 1. Calculate train statistics
    train_vals = []
    with open(train_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            train_vals.append(float(row['feature_A']))

    n_train = len(train_vals)
    assert n_train > 1, "Not enough data in train.csv to compute sample standard deviation."

    train_mean = sum(train_vals) / n_train
    train_var = sum((x - train_mean)**2 for x in train_vals) / (n_train - 1)
    train_std = math.sqrt(train_var)

    # 2. Parse test and labels
    test_data = {}
    with open(test_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            test_data[row['id']] = float(row['feature_A'])

    labels_data = {}
    with open(labels_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            labels_data[row['id']] = float(row['label'])

    # 3. Calculate MSE
    sq_errors = []
    for tid, test_val in test_data.items():
        if tid in labels_data:
            z = (test_val - train_mean) / train_std
            label = labels_data[tid]
            sq_errors.append((z - label)**2)

    assert len(sq_errors) > 0, "No matching IDs found between test.csv and labels.csv."

    mse = sum(sq_errors) / len(sq_errors)
    expected_mse_str = f"{mse:.4f}"

    # 4. Compare with the student's result
    with open(result_file, 'r') as f:
        actual_mse_str = f.read().strip()

    assert actual_mse_str == expected_mse_str, (
        f"Incorrect MSE value. Expected {expected_mse_str}, but got {actual_mse_str}. "
        "Make sure you calculated the mean and sample standard deviation from train.csv "
        "and applied them to normalize test.csv."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
