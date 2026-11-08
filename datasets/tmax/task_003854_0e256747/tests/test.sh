#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os

import pandas as pd
import pytest


def test_results_csv_exists():
    """Check that the results file was created at the expected path."""
    path = "/home/user/results.csv"
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"Output path {path} is not a file."


def test_results_accuracy():
    """Derive and verify the expected Naive Bayes probabilities from the input."""
    pred_path = "/home/user/results.csv"
    raw_path = "/home/user/raw_data.csv"

    assert os.path.exists(pred_path), f"Prediction file not found at {pred_path}"
    assert os.path.exists(raw_path), f"Input file not found at {raw_path}"

    try:
        pred = pd.read_csv(pred_path)
    except Exception as e:
        pytest.fail(f"Failed to read {pred_path} as CSV: {e}")

    try:
        raw = pd.read_csv(raw_path)
    except Exception as e:
        pytest.fail(f"Failed to read {raw_path} as CSV: {e}")

    assert 'user_id' in pred.columns, "The output file is missing the 'user_id' column."
    assert 'prob_1' in pred.columns, "The output file is missing the 'prob_1' column."

    counts = {(uid, feature): 0 for uid in range(1, 21) for feature in ('F1', 'F2')}
    for row in raw.itertuples(index=False):
        counts[(int(row.user_id), row.feature_type)] += 1

    expected_rows = []
    for uid in range(1, 21):
        count_f1 = counts[(uid, 'F1')]
        count_f2 = counts[(uid, 'F2')]
        s0 = math.log(0.65) + count_f1 * math.log(0.1) + count_f2 * math.log(0.9)
        s1 = math.log(0.35) + count_f1 * math.log(0.8) + count_f2 * math.log(0.2)
        max_s = max(s0, s1)
        exp_s0 = math.exp(s0 - max_s)
        exp_s1 = math.exp(s1 - max_s)
        prob_1 = exp_s1 / (exp_s0 + exp_s1)
        expected_rows.append((uid, float(f"{prob_1:.6f}")))

    truth = pd.DataFrame(expected_rows, columns=['user_id', 'prob_1'])

    assert len(pred) == len(truth), f"Row count mismatch: expected {len(truth)} rows, got {len(pred)}."

    if not (pred['user_id'] == truth['user_id']).all():
        pytest.fail("The 'user_id' column in results.csv does not match the expected values or is out of order.")

    mse = ((pred['prob_1'] - truth['prob_1']) ** 2).mean()
    threshold = 1e-6
    assert mse <= threshold, f"Calculated MSE of {mse:.8e} exceeds the maximum allowed threshold of {threshold:.8e}. The model probabilities are not accurate enough."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
