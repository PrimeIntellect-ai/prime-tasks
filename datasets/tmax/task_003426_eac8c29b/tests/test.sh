#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
from sklearn.metrics import mean_squared_error
import pytest

def test_run_etl_script_exists_and_executable():
    """Check that the orchestration script exists and is executable."""
    script_path = '/home/user/run_etl.sh'
    assert os.path.exists(script_path), f"Orchestration script missing at {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

def test_output_csv_exists_and_meets_metric():
    """Check that the output CSV exists, has correct columns, and meets the MSE metric."""
    output_path = '/home/user/cleaned_timeseries.csv'
    truth_path = '/tests/reference.csv'

    assert os.path.exists(output_path), f"Output CSV missing at {output_path}"
    assert os.path.exists(truth_path), f"Truth reference missing at {truth_path}"

    try:
        pred = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read output CSV: {e}")

    try:
        truth = pd.read_csv(truth_path)
    except Exception as e:
        pytest.fail(f"Failed to read truth CSV: {e}")

    assert 'frame' in pred.columns, "Output CSV missing 'frame' column"
    assert 'value' in pred.columns, "Output CSV missing 'value' column"

    assert len(pred) == len(truth), f"Length mismatch: predicted {len(pred)} rows vs truth {len(truth)} rows"

    # Calculate MSE
    mse = mean_squared_error(truth['value'], pred['value'])
    threshold = 5.0

    assert mse < threshold, f"MSE metric failed: {mse:.4f} >= {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
