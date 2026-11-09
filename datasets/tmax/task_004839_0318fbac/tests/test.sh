#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_files_exist():
    """Test that the expected output files exist."""
    expected_files = [
        "/home/user/transcript.txt",
        "/home/user/processor.cpp",
        "/home/user/processor",
        "/home/user/pipeline.log",
        "/home/user/clean_merged.csv"
    ]
    for path in expected_files:
        assert os.path.isfile(path), f"Missing expected output file: {path}"

def test_f1_score():
    """Compute the F1 score of the merged records against the ground truth."""
    pred_path = "/home/user/clean_merged.csv"
    truth_path = "/tests/ground_truth.csv"

    assert os.path.isfile(pred_path), f"Prediction file missing: {pred_path}"
    assert os.path.isfile(truth_path), f"Ground truth file missing: {truth_path}"

    try:
        pred_df = pd.read_csv(pred_path)
    except Exception as e:
        pytest.fail(f"Failed to read {pred_path} as CSV: {e}")

    try:
        truth_df = pd.read_csv(truth_path)
    except Exception as e:
        pytest.fail(f"Failed to read {truth_path} as CSV: {e}")

    required_cols = ['Name', 'City', 'Age']
    for col in required_cols:
        assert col in pred_df.columns, f"Missing column '{col}' in {pred_path}"
        assert col in truth_df.columns, f"Missing column '{col}' in {truth_path}"

    # Convert to sets of tuples for comparison
    pred_set = set(tuple(x) for x in pred_df[required_cols].astype(str).values)
    truth_set = set(tuple(x) for x in truth_df[required_cols].astype(str).values)

    intersection = len(truth_set.intersection(pred_set))

    if len(truth_set) == 0:
        f1 = 1.0 if len(pred_set) == 0 else 0.0
    else:
        precision = intersection / len(pred_set) if len(pred_set) > 0 else 0.0
        recall = intersection / len(truth_set) if len(truth_set) > 0 else 0.0

        if precision + recall == 0:
            f1 = 0.0
        else:
            f1 = 2 * (precision * recall) / (precision + recall)

    threshold = 0.90
    assert f1 >= threshold, f"F1 score {f1:.4f} is below the required threshold of {threshold:.2f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
