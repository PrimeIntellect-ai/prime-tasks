#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math

def test_regression_results():
    data_path = "/home/user/observational_data.csv"
    results_path = "/home/user/regression_results.txt"

    assert os.path.exists(data_path), f"Missing file: {data_path}"
    assert os.path.exists(results_path), f"Missing file: {results_path}"

    X = []
    Y = []

    with open(data_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            seq = row["Sequence"]
            conc = float(row["Concentration"])
            aff = float(row["Binding_Affinity"])

            if seq.startswith("ATGC") and seq.endswith("CGTA") and conc > 10.0:
                gc_count = seq.count('G') + seq.count('C')
                gc_content = gc_count / len(seq)
                X.append(gc_content)
                Y.append(aff)

    n = len(X)
    assert n > 0, "No valid sequences found in the dataset based on the criteria."

    mean_x = sum(X) / n
    mean_y = sum(Y) / n

    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(X, Y))
    denominator = sum((x - mean_x) ** 2 for x in X)

    expected_slope = numerator / denominator
    expected_intercept = mean_y - expected_slope * mean_x

    expected_lines = [
        f"Valid_Sequences: {n}",
        f"Slope: {expected_slope:.4f}",
        f"Intercept: {expected_intercept:.4f}"
    ]

    with open(results_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 3, f"Expected exactly 3 non-empty lines in {results_path}, got {len(actual_lines)}"

    assert actual_lines[0] == expected_lines[0], f"Expected '{expected_lines[0]}', got '{actual_lines[0]}'"
    assert actual_lines[1] == expected_lines[1], f"Expected '{expected_lines[1]}', got '{actual_lines[1]}'"
    assert actual_lines[2] == expected_lines[2], f"Expected '{expected_lines[2]}', got '{actual_lines[2]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
