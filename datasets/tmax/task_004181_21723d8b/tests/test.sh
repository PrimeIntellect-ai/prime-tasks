#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
from sklearn.metrics import mean_absolute_error

def test_predictions_exist():
    pred_path = '/home/user/predictions.csv'
    assert os.path.isfile(pred_path), f"Expected predictions file at {pred_path} does not exist."

def test_predictions_format_and_metric():
    pred_path = '/home/user/predictions.csv'
    truth_path = '/tests/test_hidden.csv'

    assert os.path.isfile(pred_path), f"Missing {pred_path}"
    assert os.path.isfile(truth_path), f"Missing verifier oracle {truth_path}"

    try:
        pred_df = pd.read_csv(pred_path)
    except Exception as e:
        assert False, f"Failed to read {pred_path} as CSV: {e}"

    assert 'id' in pred_df.columns, "Predictions file must contain an 'id' column."
    assert 'prediction' in pred_df.columns, "Predictions file must contain a 'prediction' column."

    try:
        truth_df = pd.read_csv(truth_path)
    except Exception as e:
        assert False, f"Failed to read {truth_path} as CSV: {e}"

    pred_df = pred_df.sort_values('id').reset_index(drop=True)
    truth_df = truth_df.sort_values('id').reset_index(drop=True)

    assert len(pred_df) == len(truth_df), f"Expected {len(truth_df)} predictions, but got {len(pred_df)}."

    pd.testing.assert_series_equal(
        pred_df['id'], truth_df['id'],
        obj="ID columns",
        check_dtype=False
    )

    mae = mean_absolute_error(truth_df['target'], pred_df['prediction'])
    assert mae <= 2.5, f"MAE is {mae:.4f}, which is greater than the threshold of 2.5."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
