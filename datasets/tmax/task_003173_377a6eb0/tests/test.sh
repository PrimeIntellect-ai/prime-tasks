#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest
import pandas as pd
import numpy as np

def test_final_output_exists():
    output_path = "/home/user/final_output.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the pipeline and save the results?"

def test_tracking_accuracy():
    output_path = "/home/user/final_output.csv"
    truth_path = "/tests/truth.csv"

    assert os.path.isfile(output_path), "Output file is missing."
    assert os.path.isfile(truth_path), "Truth file is missing."

    try:
        df_out = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as CSV: {e}")

    try:
        df_truth = pd.read_csv(truth_path)
    except Exception as e:
        pytest.fail(f"Failed to read {truth_path} as CSV: {e}")

    assert 'frame_id' in df_out.columns, "Output CSV must contain a 'frame_id' column."

    cols = ['x', 'y', 'w', 'h']
    for col in cols:
        assert col in df_out.columns, f"Output CSV must contain column '{col}'."

    df_out = df_out.sort_values('frame_id').reset_index(drop=True)
    df_truth = df_truth.sort_values('frame_id').reset_index(drop=True)

    assert len(df_out) > 0, "Output CSV is empty."
    assert len(df_out) == len(df_truth), f"Row count mismatch: expected {len(df_truth)} rows, got {len(df_out)}."

    out_vals = df_out[cols].values
    truth_vals = df_truth[cols].values

    mse = np.mean((out_vals - truth_vals)**2)

    assert mse <= 0.5, f"Tracking accuracy too low. Expected MSE <= 0.5, but got {mse:.4f}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
