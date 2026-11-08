#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_results_file_exists():
    """Check that the regression_stats.txt file exists."""
    results_path = "/home/user/results/regression_stats.txt"
    assert os.path.isfile(results_path), f"Expected results file at {results_path} is missing."

def test_regression_results_correct():
    """Check that the regression statistics are correct by recomputing them from the data."""
    results_path = "/home/user/results/regression_stats.txt"
    assert os.path.isfile(results_path), f"Cannot verify contents, {results_path} is missing."

    # 1. Read the input data using only the standard library
    weights_path = "/home/user/data/weights.csv"
    with open(weights_path, "r") as f:
        weights = [float(line.strip()) for line in f if line.strip()]

    seq_path = "/home/user/data/sequences.txt"
    with open(seq_path, "r") as f:
        sequences = [line.strip() for line in f if line.strip()]

    gs_path = "/home/user/data/gold_standard.txt"
    with open(gs_path, "r") as f:
        gold_standard = [float(line.strip()) for line in f if line.strip()]

    # 2. Recompute X values (Raw Scores)
    base_map = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
    X = []
    for seq in sequences:
        w = []
        for i, b in enumerate(seq):
            # Row-major 4x20: index = row * 20 + col
            idx = base_map[b] * 20 + i
            w.append(weights[idx])
        # Crucial floating-point stability step: sort before summing
        w.sort()
        X.append(sum(w))

    Y = gold_standard

    # 3. Compute linear regression and MSE
    n = len(X)
    mean_x = sum(X) / n
    mean_y = sum(Y) / n

    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(X, Y))
    denominator = sum((x - mean_x) ** 2 for x in X)

    expected_slope = numerator / denominator
    expected_intercept = mean_y - expected_slope * mean_x
    expected_mse = sum((y - (expected_slope * x + expected_intercept)) ** 2 for x, y in zip(X, Y)) / n

    # 4. Parse the student's results
    with open(results_path, "r") as f:
        content = f.read()

    slope_match = re.search(r"Slope:\s*([\d.-]+)", content)
    intercept_match = re.search(r"Intercept:\s*([\d.-]+)", content)
    mse_match = re.search(r"MSE:\s*([\d.-]+)", content)

    assert slope_match is not None, "Could not find 'Slope: <value>' in regression_stats.txt"
    assert intercept_match is not None, "Could not find 'Intercept: <value>' in regression_stats.txt"
    assert mse_match is not None, "Could not find 'MSE: <value>' in regression_stats.txt"

    actual_slope = float(slope_match.group(1))
    actual_intercept = float(intercept_match.group(1))
    actual_mse = float(mse_match.group(1))

    # 5. Assert values with a small tolerance for rounding differences
    tolerance = 0.0002

    assert abs(actual_slope - expected_slope) <= tolerance, \
        f"Slope mismatch. Expected approx {expected_slope:.4f}, got {actual_slope}"

    assert abs(actual_intercept - expected_intercept) <= tolerance, \
        f"Intercept mismatch. Expected approx {expected_intercept:.4f}, got {actual_intercept}"

    assert abs(actual_mse - expected_mse) <= tolerance, \
        f"MSE mismatch. Expected approx {expected_mse:.4f}, got {actual_mse}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
