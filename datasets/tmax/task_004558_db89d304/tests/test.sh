#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_c_source_exists():
    path = "/home/user/etl_pipeline.c"
    assert os.path.isfile(path), f"File {path} does not exist. The C source file is missing."

def test_predictions_file_exists():
    path = "/home/user/predictions.csv"
    assert os.path.isfile(path), f"File {path} does not exist. The pipeline did not produce the expected output file."

def test_predictions_content():
    golden_path = "/tests/.golden_predictions.csv"
    pred_path = "/home/user/predictions.csv"

    assert os.path.isfile(golden_path), f"Golden file {golden_path} is missing."
    assert os.path.isfile(pred_path), f"Predictions file {pred_path} is missing."

    with open(golden_path, 'r') as f:
        golden_lines = [line.strip() for line in f.readlines() if line.strip()]

    with open(pred_path, 'r') as f:
        pred_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(pred_lines) == len(golden_lines), f"Row count mismatch: expected {len(golden_lines)} rows, got {len(pred_lines)} rows."

    for i, (expected, actual) in enumerate(zip(golden_lines, pred_lines)):
        assert actual == expected, f"Mismatch at row {i + 1}:\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
