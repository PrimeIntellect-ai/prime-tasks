#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np

def test_metrics_csv_exists():
    assert os.path.isfile("/app/metrics.csv"), "The output file /app/metrics.csv is missing."

def test_volume_mse_metric():
    test_metrics_csv_exists()

    try:
        truth = pd.read_csv('/tests/ground_truth.csv').sort_values('filename').reset_index(drop=True)
    except Exception as e:
        raise AssertionError(f"Failed to read /tests/ground_truth.csv: {e}")

    try:
        pred = pd.read_csv('/app/metrics.csv').sort_values('filename').reset_index(drop=True)
    except Exception as e:
        raise AssertionError(f"Failed to read /app/metrics.csv: {e}. Ensure it is a valid CSV file.")

    assert len(truth) == len(pred), f"Row count mismatch: expected {len(truth)} rows, got {len(pred)} rows."

    assert 'volume' in pred.columns, "The 'volume' column is missing from /app/metrics.csv."
    assert 'filename' in pred.columns, "The 'filename' column is missing from /app/metrics.csv."
    assert 'max_extrusion' in pred.columns, "The 'max_extrusion' column is missing from /app/metrics.csv."

    # Check that filenames match exactly
    for t_file, p_file in zip(truth['filename'], pred['filename']):
        assert t_file == p_file, f"Filename mismatch: expected '{t_file}', got '{p_file}'"

    # Compute MSE for volume
    mse = np.mean((truth['volume'].values - pred['volume'].values)**2)
    threshold = 0.01

    assert mse <= threshold, f"Volume MSE is {mse:.6f}, which exceeds the threshold of {threshold}. Agent's volumes: {pred['volume'].values}, Expected: {truth['volume'].values}"

def test_max_extrusion_mse_metric():
    # While the primary metric is volume MSE, we should also ensure max_extrusion is accurate
    test_metrics_csv_exists()

    truth = pd.read_csv('/tests/ground_truth.csv').sort_values('filename').reset_index(drop=True)
    pred = pd.read_csv('/app/metrics.csv').sort_values('filename').reset_index(drop=True)

    if len(truth) == len(pred) and 'max_extrusion' in pred.columns:
        mse_ext = np.mean((truth['max_extrusion'].values - pred['max_extrusion'].values)**2)
        threshold = 0.01
        assert mse_ext <= threshold, f"Max Extrusion MSE is {mse_ext:.6f}, which exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
