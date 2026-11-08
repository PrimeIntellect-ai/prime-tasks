#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def test_correlation_result():
    csv_path = "/home/user/benchmarks.csv"
    result_path = "/home/user/correlation.txt"

    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    X = []
    Y = []
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')
        # Skip header
        for line in lines[1:]:
            parts = line.split(',')
            if len(parts) == 3:
                try:
                    inf_ms = float(parts[1])
                    if inf_ms >= 0:
                        conf = float(parts[2])
                        X.append(inf_ms)
                        Y.append(conf)
                except ValueError:
                    # Ignore rows with non-numeric inference_ms or confidence_score
                    pass

    n = len(X)
    assert n > 1, "Not enough valid rows to compute correlation."

    sum_x = sum(X)
    sum_y = sum(Y)
    sum_x2 = sum(x*x for x in X)
    sum_y2 = sum(y*y for y in Y)
    sum_xy = sum(x*y for x, y in zip(X, Y))

    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2))

    corr = numerator / denominator
    expected_val = f"{corr:.3f}"

    # Handle negative zero just in case
    if expected_val == "-0.000":
        expected_val = "0.000"

    with open(result_path, 'r') as f:
        actual_val = f.read().strip()

    assert actual_val == expected_val, f"Expected correlation {expected_val} in {result_path}, but got '{actual_val}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
