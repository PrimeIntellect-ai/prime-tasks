#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import numpy as np

def test_predictions_rmse():
    pred_path = '/home/user/predictions.csv'
    truth_path = '/tests/hidden_truth.csv'

    # Check that the required files exist
    assert os.path.exists(pred_path), f"Output file is missing: {pred_path}"
    assert os.path.exists(truth_path), f"Truth file is missing: {truth_path}"

    # Load the predictions and the truth
    try:
        pred = pd.read_csv(pred_path)
    except Exception as e:
        assert False, f"Failed to read predictions.csv: {e}"

    try:
        truth = pd.read_csv(truth_path)
    except Exception as e:
        assert False, f"Failed to read hidden_truth.csv: {e}"

    # Validate columns in predictions
    assert 'time_sec' in pred.columns, "Predictions file is missing the 'time_sec' column."
    assert 'predicted_yield' in pred.columns, "Predictions file is missing the 'predicted_yield' column."

    # Merge on time_sec to align predictions with truth
    merged = pd.merge(truth, pred, on='time_sec')

    # Ensure all test set predictions are present
    assert len(merged) == len(truth), (
        f"Missing predictions. Expected {len(truth)} matching rows, "
        f"but found {len(merged)} after merging on 'time_sec'."
    )

    # Calculate Root Mean Squared Error (RMSE)
    rmse = np.sqrt(np.mean((merged['reaction_yield'] - merged['predicted_yield'])**2))

    # Assert against the threshold
    assert rmse <= 4.0, f"RMSE {rmse:.4f} is greater than the required threshold of 4.0."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
