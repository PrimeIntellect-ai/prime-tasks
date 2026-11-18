#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def test_analysis_results():
    csv_path = '/home/user/binding_data.csv'
    json_path = '/home/user/analysis_results.json'

    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
    assert os.path.isfile(json_path), f"Output file {json_path} is missing."

    # Calculate truth values
    X = []
    Y = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            seq = row['sequence']
            score = float(row['score'])
            gc_count = seq.count('G') + seq.count('C')
            gc_frac = gc_count / len(seq)
            X.append(gc_frac)
            Y.append(score)

    N = len(X)
    assert N > 1, "Need at least 2 data points."

    mean_X = sum(X) / N
    mean_Y = sum(Y) / N

    cov_XY = sum((x - mean_X) * (y - mean_Y) for x, y in zip(X, Y))
    var_X = sum((x - mean_X)**2 for x in X)

    slope = cov_XY / var_X
    intercept = mean_Y - slope * mean_X

    var_Y = sum((y - mean_Y)**2 for y in Y) / (N - 1)
    std_Y = math.sqrt(var_Y)

    # Read student JSON
    try:
        with open(json_path, 'r') as f:
            student_data = json.load(f)
    except Exception as e:
        assert False, f"Failed to parse {json_path} as JSON: {e}"

    required_keys = ["slope", "intercept", "mean_score", "std_score"]
    for key in required_keys:
        assert key in student_data, f"Missing key '{key}' in {json_path}"

    tol = 0.0002

    assert abs(student_data['slope'] - slope) <= tol, \
        f"Slope is incorrect. Expected ~{slope:.4f}, got {student_data['slope']}"
    assert abs(student_data['intercept'] - intercept) <= tol, \
        f"Intercept is incorrect. Expected ~{intercept:.4f}, got {student_data['intercept']}"
    assert abs(student_data['mean_score'] - mean_Y) <= tol, \
        f"Mean score is incorrect. Expected ~{mean_Y:.4f}, got {student_data['mean_score']}"
    assert abs(student_data['std_score'] - std_Y) <= tol, \
        f"Std score is incorrect. Expected ~{std_Y:.4f}, got {student_data['std_score']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
