#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import pandas as pd
import numpy as np

def test_filtered_signals_mae():
    """Check if the filtered signals CSV exists and has an acceptable MAE."""
    pred_path = '/home/user/filtered_signals.csv'
    truth_path = '/tests/ground_truth_filtered.csv'

    assert os.path.isfile(pred_path), f"Output file is missing: {pred_path}"
    assert os.path.isfile(truth_path), f"Ground truth file is missing: {truth_path}"

    try:
        pred = pd.read_csv(pred_path, header=None).values
    except Exception as e:
        pytest.fail(f"Failed to read prediction CSV: {e}")

    try:
        truth = pd.read_csv(truth_path, header=None).values
    except Exception as e:
        pytest.fail(f"Failed to read ground truth CSV: {e}")

    assert pred.shape == truth.shape, f"Shape mismatch: expected {truth.shape}, got {pred.shape}"

    mae = np.mean(np.abs(pred - truth))
    assert mae <= 2.5, f"MAE is too high: {mae} > 2.5. The output signals do not match the ground truth closely enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
