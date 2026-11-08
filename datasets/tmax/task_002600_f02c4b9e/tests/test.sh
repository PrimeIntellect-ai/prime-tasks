#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import pandas as pd

def calculate_f1(pred_path, truth_path):
    try:
        pred_df = pd.read_csv(pred_path)
        truth_df = pd.read_csv(truth_path)

        # Create a set of tuples for exact row matching
        pred_set = set(tuple(row) for row in pred_df.to_numpy())
        truth_set = set(tuple(row) for row in truth_df.to_numpy())

        if not pred_set:
            return 0.0

        true_positives = len(pred_set.intersection(truth_set))
        precision = true_positives / len(pred_set)
        recall = true_positives / len(truth_set)

        if precision + recall == 0:
            return 0.0

        f1 = 2 * (precision * recall) / (precision + recall)
        return f1
    except Exception as e:
        return 0.0

def test_clean_records_f1_score():
    pred_path = '/home/user/clean_records.csv'
    truth_path = '/tests/truth_records.csv'

    assert os.path.isfile(pred_path), f"Output file missing: {pred_path}"
    assert os.path.isfile(truth_path), f"Truth file missing: {truth_path}"

    score = calculate_f1(pred_path, truth_path)

    assert score >= 0.95, f"F1 score is {score:.4f}, which is below the threshold of 0.95"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
