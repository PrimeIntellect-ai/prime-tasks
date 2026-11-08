#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest

def compute_expected_results():
    weights_path = '/home/user/model/weights.json'
    assert os.path.exists(weights_path), f"{weights_path} is missing."

    with open(weights_path, 'r') as f:
        w = json.load(f)

    W1 = w['W1']
    b1 = w['b1']
    W2 = w['W2']
    b2 = w['b2']

    data_dir = '/home/user/data'
    assert os.path.exists(data_dir), f"{data_dir} is missing."

    files = sorted([f for f in os.listdir(data_dir) if f.endswith('.csv')])

    results = []
    for file in files:
        filepath = os.path.join(data_dir, file)
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        if not rows:
            results.append((file, 0.0))
            continue

        positive_count = 0
        for row in rows:
            x = [float(row['feature1']), float(row['feature2']), float(row['feature3'])]

            # z1 = x.dot(W1) + b1
            z1 = []
            for col_idx in range(len(W1[0])):
                val = sum(x[i] * W1[i][col_idx] for i in range(len(x))) + b1[col_idx]
                z1.append(val)

            # a1 = relu(z1)
            a1 = [max(0, val) for val in z1]

            # z2 = a1.dot(W2) + b2
            z2 = sum(a1[i] * W2[i][0] for i in range(len(a1))) + b2[0]

            # sigmoid(z2) >= 0.5 is mathematically equivalent to z2 >= 0
            if z2 >= 0:
                positive_count += 1

        rate = positive_count / len(rows)
        results.append((file, round(rate, 4)))

    return results

def test_results_csv_exists_and_correct():
    expected_results = compute_expected_results()

    results_path = '/home/user/results.csv'
    assert os.path.isfile(results_path), f"The output file {results_path} was not created."

    with open(results_path, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{results_path} is empty.")

        assert header == ['filename', 'positive_rate'], f"Header in {results_path} is incorrect. Expected ['filename', 'positive_rate'], got {header}."

        actual_results = []
        for row_num, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Row {row_num} in {results_path} does not have exactly 2 columns."
            try:
                rate = float(row[1])
            except ValueError:
                pytest.fail(f"Invalid positive_rate '{row[1]}' in row {row_num} of {results_path}. Must be a number.")
            actual_results.append((row[0], rate))

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} data rows in {results_path}, but found {len(actual_results)}."

    for expected, actual in zip(expected_results, actual_results):
        exp_filename, exp_rate = expected
        act_filename, act_rate = actual

        assert act_filename == exp_filename, f"Expected filename '{exp_filename}' but got '{act_filename}'. Ensure rows are sorted alphabetically."
        assert abs(exp_rate - act_rate) <= 1e-4, f"For file '{exp_filename}', expected positive_rate {exp_rate:.4f} but got {act_rate}. Make sure rounding and logic are correct."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
