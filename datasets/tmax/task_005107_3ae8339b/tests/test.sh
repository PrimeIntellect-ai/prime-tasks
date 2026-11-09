#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_positive_predictions_file():
    output_path = "/home/user/positive_predictions.csv"
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    # Read weights
    weights = {}
    with open("/home/user/weights.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            weights[row["feature"]] = float(row["weight"])

    bias = weights.get("bias", 0.0)
    w1 = weights.get("f1", 0.0)
    w2 = weights.get("f2", 0.0)

    # Read data and compute expected
    expected_positive = []
    with open("/home/user/data.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_id = int(row["id"])

            # Impute and parse
            f1_str = row["f1"].strip()
            f1_val = float(f1_str) if f1_str else 0.0

            f2_str = row["f2"].strip()
            f2_val = float(f2_str) if f2_str else 0.0

            # Cap
            f1_val = max(-10.0, min(10.0, f1_val))
            f2_val = max(-10.0, min(10.0, f2_val))

            # Predict
            pred = bias + (f1_val * w1) + (f2_val * w2)

            if pred > 0.0:
                expected_positive.append((row_id, pred))

    expected_positive.sort(key=lambda x: x[0])

    # Read output
    actual_positive = []
    with open(output_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Expected 2 columns in output, got {len(row)} in row: {row}"
            try:
                actual_id = int(row[0])
                actual_pred = float(row[1])
                actual_positive.append((actual_id, actual_pred))
            except ValueError:
                pytest.fail(f"Could not parse row as (int, float): {row}. Make sure there is no header.")

    # Check length
    assert len(actual_positive) == len(expected_positive), f"Expected {len(expected_positive)} positive predictions, but got {len(actual_positive)}."

    # Compare values
    for (exp_id, exp_pred), (act_id, act_pred) in zip(expected_positive, actual_positive):
        assert exp_id == act_id, f"Expected id {exp_id}, but got {act_id}."
        assert abs(exp_pred - act_pred) < 1e-5, f"For id {exp_id}, expected prediction {exp_pred}, but got {act_pred}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
