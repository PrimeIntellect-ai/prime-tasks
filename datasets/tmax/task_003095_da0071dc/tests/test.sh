#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import pandas as pd

def test_summary_csv_exists():
    path = "/home/user/summary.csv"
    assert os.path.isfile(path), f"Output file {path} does not exist."

def test_summary_csv_metric():
    pred_path = "/home/user/summary.csv"
    truth_path = "/tests/truth_summary.csv"

    assert os.path.isfile(pred_path), f"Missing prediction file: {pred_path}"
    assert os.path.isfile(truth_path), f"Missing truth file: {truth_path}"

    try:
        pred = pd.read_csv(pred_path)
        assert 'merchant_id' in pred.columns and 'total_amount' in pred.columns, "Output CSV must have 'merchant_id' and 'total_amount' columns."
        pred = pred.set_index('merchant_id')['total_amount']
    except Exception as e:
        pytest.fail(f"Failed to read or parse {pred_path}: {e}")

    try:
        truth = pd.read_csv(truth_path).set_index('merchant_id')['total_amount']
    except Exception as e:
        pytest.fail(f"Failed to read or parse {truth_path}: {e}")

    assert len(pred) == len(truth), f"Number of merchants in output ({len(pred)}) does not match truth ({len(truth)})."

    pred = pred.sort_index()
    truth = truth.sort_index()

    assert pred.index.equals(truth.index), "The merchant_ids in the output do not match the truth exactly."

    max_ae = (pred - truth).abs().max()

    assert max_ae <= 0.05, f"Maximum absolute error {max_ae} exceeds threshold of 0.05."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
