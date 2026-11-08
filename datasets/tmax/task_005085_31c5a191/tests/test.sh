#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_anomalies_csv_exists():
    pred_path = "/home/user/anomalies.csv"
    assert os.path.exists(pred_path), f"Expected output file {pred_path} does not exist."
    assert os.path.isfile(pred_path), f"Expected {pred_path} to be a file."

def test_anomalies_f1_score():
    pred_path = "/home/user/anomalies.csv"
    gt_path = "/tests/anomalies_gt.csv"

    assert os.path.exists(pred_path), "Prediction file missing."
    assert os.path.exists(gt_path), "Ground truth file missing."

    try:
        df_pred = pd.read_csv(pred_path)
    except Exception as e:
        pytest.fail(f"Failed to read {pred_path} as CSV: {e}")

    try:
        df_gt = pd.read_csv(gt_path)
    except Exception as e:
        pytest.fail(f"Failed to read {gt_path} as CSV: {e}")

    # Ensure columns match expected or at least we can merge
    expected_cols = ['date', 'server_name', 'value']
    for col in expected_cols:
        assert col in df_pred.columns, f"Column '{col}' missing in {pred_path}"

    # Convert values to float to avoid string mismatch issues if any
    df_pred['value'] = pd.to_numeric(df_pred['value'], errors='coerce')
    df_gt['value'] = pd.to_numeric(df_gt['value'], errors='coerce')

    # Drop NAs if any were introduced
    df_pred = df_pred.dropna(subset=['date', 'server_name', 'value'])

    # Merge to find True Positives, False Positives, False Negatives
    merged = pd.merge(df_pred, df_gt, on=['date', 'server_name', 'value'], how='outer', indicator=True)

    tp = len(merged[merged['_merge'] == 'both'])
    fp = len(merged[merged['_merge'] == 'left_only'])
    fn = len(merged[merged['_merge'] == 'right_only'])

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    assert f1 >= 0.95, f"F1 score {f1:.4f} is below the threshold of 0.95 (TP={tp}, FP={fp}, FN={fn})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
