#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import pandas as pd

def test_process_script_exists_and_executable():
    path = "/home/user/process.sh"
    assert os.path.isfile(path), f"Missing script: {path}"
    assert os.access(path, os.X_OK), f"Script {path} is not executable"

def test_pipeline_log_exists():
    path = "/home/user/pipeline.log"
    assert os.path.isfile(path), f"Missing log file: {path}"
    assert os.path.getsize(path) > 0, f"Log file {path} is empty"

def test_anomalies_output_exists_and_f1_score():
    pred_path = "/home/user/anomalies.csv"
    truth_path = "/tests/ground_truth.csv"

    assert os.path.isfile(pred_path), f"Missing output file: {pred_path}"

    try:
        truth = pd.read_csv(truth_path, names=['timestamp', 'sensor_id'])
    except Exception as e:
        pytest.fail(f"Failed to read ground truth: {e}")

    try:
        pred = pd.read_csv(pred_path, names=['timestamp', 'sensor_id'])
    except Exception as e:
        pytest.fail(f"Failed to read predictions: {e}")

    truth_set = set(zip(truth['timestamp'], truth['sensor_id']))
    pred_set = set(zip(pred['timestamp'], pred['sensor_id']))

    tp = len(truth_set.intersection(pred_set))
    fp = len(pred_set - truth_set)
    fn = len(truth_set - pred_set)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 0.98, f"F1 score {f1:.4f} is below the threshold of 0.98. Precision: {precision:.4f}, Recall: {recall:.4f}"

def test_anomalies_sorted():
    pred_path = "/home/user/anomalies.csv"
    assert os.path.isfile(pred_path), f"Missing output file: {pred_path}"

    try:
        pred = pd.read_csv(pred_path, names=['timestamp', 'sensor_id'])
    except Exception as e:
        pytest.fail(f"Failed to read predictions: {e}")

    # Check if sorted chronologically by timestamp
    assert pred['timestamp'].is_monotonic_increasing, "The file anomalies.csv is not sorted chronologically by timestamp"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
