#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np

def test_interpolated_pressure_csv():
    pred_path = '/home/user/interpolated_pressure.csv'
    truth_path = '/tests/truth.csv'

    assert os.path.exists(pred_path), f"Output file {pred_path} does not exist."
    assert os.path.exists(truth_path), f"Truth file {truth_path} does not exist."

    try:
        truth = pd.read_csv(truth_path)
        pred = pd.read_csv(pred_path)
    except Exception as e:
        assert False, f"Failed to read CSV files: {e}"

    assert 'timestamp' in pred.columns and 'pressure' in pred.columns, "Output CSV must have 'timestamp' and 'pressure' columns."

    merged = pd.merge(truth, pred, on='timestamp', suffixes=('_true', '_pred'), how='inner')

    assert len(merged) >= 50, f"Expected at least 50 matching timestamps, but got {len(merged)}."

    mse = np.mean((merged['pressure_true'] - merged['pressure_pred'])**2)

    assert mse <= 2.0, f"MSE is {mse:.4f}, which is greater than the allowed threshold of 2.0."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
