#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import pandas as pd
import numpy as np

def test_processed_features_mse():
    output_path = "/home/user/processed_features.csv"
    ref_path = "/tests/reference_features.csv"

    assert os.path.isfile(output_path), f"Output file missing: {output_path}"
    assert os.path.isfile(ref_path), f"Reference file missing: {ref_path}"

    try:
        df_out = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as CSV: {e}")

    try:
        df_ref = pd.read_csv(ref_path)
    except Exception as e:
        pytest.fail(f"Failed to read {ref_path} as CSV: {e}")

    assert "std_dev" in df_out.columns, "Output CSV is missing the 'std_dev' column."
    assert "std_dev" in df_ref.columns, "Reference CSV is missing the 'std_dev' column."

    assert len(df_out) == len(df_ref), f"Row count mismatch: output has {len(df_out)} rows, reference has {len(df_ref)} rows."

    # Compute Mean Squared Error (MSE)
    mse = np.mean((df_out["std_dev"] - df_ref["std_dev"]) ** 2)

    threshold = 1e-6
    assert mse < threshold, f"MSE of std_dev column is {mse}, which is not strictly less than the threshold {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
