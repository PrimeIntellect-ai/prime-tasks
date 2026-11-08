#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np
import pytest

def test_predictions_file_exists():
    pred_path = '/home/user/predictions.txt'
    assert os.path.exists(pred_path), f"Error: {pred_path} not found."
    assert os.path.isfile(pred_path), f"Error: {pred_path} is not a file."

def test_predictions_metric():
    pred_path = '/home/user/predictions.txt'
    assert os.path.exists(pred_path), f"Error: {pred_path} not found."

    # Re-derive the reference truth
    data_path = '/app/data.csv'
    assert os.path.exists(data_path), f"Error: {data_path} not found."

    data = np.loadtxt(data_path, delimiter=',')
    train = data[:800]
    test = data[800:]

    # Calculate mean and population std on training set only
    train_mean = np.mean(train, axis=0)
    train_std = np.std(train, axis=0)

    # Standardize test set using training parameters
    test_norm = (test - train_mean) / train_std

    # Ground truth weights from the image
    weights = np.array([0.35, 0.80, -0.25])
    expected_preds = np.dot(test_norm, weights)

    # Load agent's predictions
    try:
        agent_preds = np.loadtxt(pred_path)
    except Exception as e:
        pytest.fail(f"Error parsing {pred_path}: {e}")

    # Verify the structure of the output
    assert agent_preds.shape == (200,), f"Expected exactly 200 predictions, but got shape {agent_preds.shape}"

    # Compute the Mean Absolute Error (MAE) metric
    mae = np.mean(np.abs(expected_preds - agent_preds))

    # Assert against the threshold
    threshold = 0.001
    assert mae <= threshold, f"FAILURE: MAE of {mae:.6f} exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
