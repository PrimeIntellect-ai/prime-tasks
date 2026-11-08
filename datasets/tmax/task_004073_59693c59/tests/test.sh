#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import pandas as pd
import numpy as np

def test_anomalies_csv_exists_and_format():
    """Check if the anomalies CSV exists and has the correct header."""
    path = '/home/user/anomalies.csv'
    assert os.path.isfile(path), f"{path} does not exist."

    df = pd.read_csv(path)
    expected_cols = ['timestamp_sec', 'sensor_id', 'euclidean_distance']
    for col in expected_cols:
        assert col in df.columns, f"Column '{col}' missing in {path}"

def test_metrics_f1_and_mae():
    """Calculate F1 and MAE against the ground truth and assert thresholds."""
    pred_path = '/home/user/anomalies.csv'
    true_path = '/tests/ground_truth_anomalies.csv'

    assert os.path.isfile(pred_path), f"Prediction file {pred_path} is missing."
    assert os.path.isfile(true_path), f"Ground truth file {true_path} is missing."

    df_pred = pd.read_csv(pred_path)
    df_true = pd.read_csv(true_path)

    pred_timestamps = set(df_pred['timestamp_sec'])
    true_timestamps = set(df_true['timestamp_sec'])

    tp = len(pred_timestamps.intersection(true_timestamps))
    fp = len(pred_timestamps - true_timestamps)
    fn = len(true_timestamps - pred_timestamps)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 0.90, f"F1-score is {f1:.3f}, expected >= 0.90"

    merged = pd.merge(df_pred, df_true, on='timestamp_sec', suffixes=('_pred', '_true'))
    if len(merged) > 0:
        mae = np.mean(np.abs(merged['euclidean_distance_pred'] - merged['euclidean_distance_true']))
    else:
        mae = 999.0

    assert mae <= 2.0, f"MAE is {mae:.3f}, expected <= 2.0"

def test_storage_management():
    """Check that extracted raw frames were deleted to free up space."""
    processing_dir = '/home/user/processing'
    if os.path.isdir(processing_dir):
        extensions = ['*.png', '*.jpg', '*.jpeg', '*.bmp', '*.raw', '*.rgb', '*.bin']
        for ext in extensions:
            files = glob.glob(os.path.join(processing_dir, '**', ext), recursive=True)
            assert len(files) == 0, f"Found extracted raw frames left in {processing_dir}: {files[0]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
