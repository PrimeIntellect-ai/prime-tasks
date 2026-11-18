#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np
import pytest

def test_results_file_exists():
    assert os.path.isfile('/home/user/results.csv'), "The results file /home/user/results.csv was not generated."

def test_mse_metric_threshold():
    pred_path = '/home/user/results.csv'
    truth_path = '/tests/ground_truth.csv'

    assert os.path.isfile(pred_path), f"Missing predictions file: {pred_path}"
    assert os.path.isfile(truth_path), f"Missing ground truth file: {truth_path}"

    try:
        pred = pd.read_csv(pred_path, names=['event_id', 'pred_charge'])
    except Exception as e:
        pytest.fail(f"Failed to read predictions file {pred_path}: {e}")

    try:
        truth = pd.read_csv(truth_path, names=['event_id', 'true_charge'])
    except Exception as e:
        pytest.fail(f"Failed to read ground truth file {truth_path}: {e}")

    merged = pd.merge(truth, pred, on='event_id')

    expected_count = 100
    actual_count = len(merged)
    assert actual_count >= expected_count, f"Missing predictions. Expected at least {expected_count} matching event_ids, got {actual_count}"

    # Calculate Mean Squared Error
    mse = np.mean((merged['true_charge'] - merged['pred_charge'])**2)

    threshold = 0.05
    assert mse < threshold, f"Failure: MSE exceeds {threshold} threshold. Computed MSE: {mse}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
