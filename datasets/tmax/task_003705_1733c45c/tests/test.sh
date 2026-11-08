#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_output_exists_and_sorted():
    pred_path = "/home/user/anomalies.csv"
    assert os.path.isfile(pred_path), f"Output file not found: {pred_path}"

    pred_df = pd.read_csv(pred_path)
    expected_cols = ['bucket_start_time', 'sensor_id', 'anomaly_count']
    for col in expected_cols:
        assert col in pred_df.columns, f"Missing column in output: {col}"

    # Verify sorting: numerically by bucket_start_time ascending, then by sensor_id alphabetically
    sorted_df = pred_df.sort_values(by=['bucket_start_time', 'sensor_id']).reset_index(drop=True)
    pred_df_reset = pred_df.reset_index(drop=True)

    pd.testing.assert_frame_equal(
        pred_df_reset,
        sorted_df,
        check_like=False,
        obj="Output CSV sorting"
    )

def test_anomaly_f1_score():
    pred_path = "/home/user/anomalies.csv"
    truth_path = "/tests/truth_anomalies.csv"

    assert os.path.isfile(pred_path), f"Output file not found: {pred_path}"
    assert os.path.isfile(truth_path), f"Truth file not found: {truth_path}"

    pred_df = pd.read_csv(pred_path)
    truth_df = pd.read_csv(truth_path)

    # Merge predictions with truth
    merged = pd.merge(
        truth_df,
        pred_df,
        on=['bucket_start_time', 'sensor_id'],
        how='outer',
        suffixes=('_true', '_pred')
    )

    merged['anomaly_count_true'] = merged['anomaly_count_true'].fillna(0)
    merged['anomaly_count_pred'] = merged['anomaly_count_pred'].fillna(0)

    # Calculate TP, FP, FN based on counts
    # For each bucket-sensor pair, if truth has N anomalies and pred has M:
    # True Positives = min(N, M)
    # False Positives = max(0, M - N)
    # False Negatives = max(0, N - M)
    merged['tp'] = merged[['anomaly_count_true', 'anomaly_count_pred']].min(axis=1)
    merged['fp'] = (merged['anomaly_count_pred'] - merged['anomaly_count_true']).clip(lower=0)
    merged['fn'] = (merged['anomaly_count_true'] - merged['anomaly_count_pred']).clip(lower=0)

    tp = merged['tp'].sum()
    fp = merged['fp'].sum()
    fn = merged['fn'].sum()

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

    assert f1 >= 0.99, f"F1 Score {f1:.4f} is below the threshold of 0.99. Precision: {precision:.4f}, Recall: {recall:.4f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
