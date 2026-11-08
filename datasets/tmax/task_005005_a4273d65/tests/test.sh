#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np

def test_aggregated_metrics_exists():
    assert os.path.isfile("/home/user/aggregated_metrics.csv"), "The output file /home/user/aggregated_metrics.csv does not exist."

def test_aggregated_metrics_mse():
    user_file = "/home/user/aggregated_metrics.csv"
    truth_file = "/tests/ground_truth.csv"

    assert os.path.isfile(user_file), f"Output file missing: {user_file}"
    assert os.path.isfile(truth_file), f"Ground truth file missing: {truth_file}"

    try:
        user_df = pd.read_csv(user_file)
    except Exception as e:
        assert False, f"Failed to read {user_file} as CSV: {e}"

    try:
        truth_df = pd.read_csv(truth_file)
    except Exception as e:
        assert False, f"Failed to read {truth_file} as CSV: {e}"

    expected_cols = ['window_end_ts', 'host', 'metric_name', 'rolling_avg']
    for col in expected_cols:
        assert col in user_df.columns, f"Column '{col}' is missing from the output CSV."

    merged = pd.merge(user_df, truth_df, on=['window_end_ts', 'host', 'metric_name'], suffixes=('_user', '_truth'))

    assert len(merged) >= len(truth_df) * 0.9, f"Output is missing too many rows. Expected at least {int(len(truth_df) * 0.9)}, got {len(merged)} matching rows."

    mse = np.mean((merged['rolling_avg_user'] - merged['rolling_avg_truth']) ** 2)

    assert mse <= 0.01, f"Mean Squared Error (MSE) is too high. Expected <= 0.01, got {mse:.4f}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
