#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import pytest

def calculate_f1(pred_path, truth_path):
    try:
        pred_df = pd.read_csv(pred_path)
        truth_df = pd.read_csv(truth_path)
    except Exception as e:
        return 0.0, f"Error reading CSVs: {e}"

    # Convert to sets of tuples for comparison
    pred_set = set([tuple(x) for x in pred_df.to_numpy()])
    truth_set = set([tuple(x) for x in truth_df.to_numpy()])

    if not pred_set and not truth_set:
        return 1.0, "Both sets empty"
    if not pred_set or not truth_set:
        return 0.0, "One set is empty"

    tp = len(pred_set.intersection(truth_set))
    fp = len(pred_set - truth_set)
    fn = len(truth_set - pred_set)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0

    if precision + recall == 0:
        return 0.0, "Precision and recall are 0"

    f1 = 2 * (precision * recall) / (precision + recall)
    return f1, f"TP: {tp}, FP: {fp}, FN: {fn}"

def test_critical_events_csv_f1_score():
    pred_path = "/home/user/critical_events.csv"
    truth_path = "/tests/ground_truth.csv"

    assert os.path.exists(pred_path), f"Output file missing: {pred_path}"
    assert os.path.exists(truth_path), f"Ground truth file missing: {truth_path}"

    f1_score, details = calculate_f1(pred_path, truth_path)

    assert f1_score >= 0.95, f"F1 score {f1_score:.4f} is below the threshold of 0.95. Details: {details}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
