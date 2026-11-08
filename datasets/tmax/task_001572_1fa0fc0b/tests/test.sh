#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def get_column(data, col_idx):
    return [row[col_idx] for row in data]

def mean(values):
    return sum(values) / len(values)

def std(values, m):
    n = len(values)
    variance = sum((x - m) ** 2 for x in values) / (n - 1)
    return math.sqrt(variance)

def covariance(col1, col2, m1, m2):
    n = len(col1)
    return sum((x - m1) * (y - m2) for x, y in zip(col1, col2)) / (n - 1)

def compute_expected_result(csv_path):
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = [[float(val) for val in row] for row in reader]

    train = data[:50]
    test = data[50:]

    # Compute train means and stds
    train_means = [mean(get_column(train, c)) for c in range(3)]
    train_stds = [std(get_column(train, c), train_means[c]) for c in range(3)]

    # Standardize test set
    test_std = []
    for row in test:
        test_std.append([(row[c] - train_means[c]) / train_stds[c] for c in range(3)])

    # Compute covariance matrix of standardized test set
    test_std_cols = [get_column(test_std, c) for c in range(3)]
    test_std_means = [mean(col) for col in test_std_cols]

    cov_sum = 0.0
    for i in range(3):
        for j in range(3):
            cov_sum += covariance(test_std_cols[i], test_std_cols[j], test_std_means[i], test_std_means[j])

    return f"{cov_sum:.4f}"

def test_result_file_exists_and_correct():
    result_file = "/home/user/result.txt"
    data_file = "/home/user/data.csv"

    assert os.path.exists(data_file), f"Data file {data_file} is missing."
    assert os.path.exists(result_file), f"Result file {result_file} was not created."

    expected_value = compute_expected_result(data_file)

    with open(result_file, "r") as f:
        actual_value = f.read().strip()

    assert actual_value == expected_value, f"Expected {expected_value} in {result_file}, but got {actual_value}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
