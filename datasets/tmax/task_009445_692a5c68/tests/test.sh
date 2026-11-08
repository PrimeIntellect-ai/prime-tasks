#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_top_features_file():
    """Verify that top_features.txt exists and contains the correct features."""
    file_path = "/home/user/top_features.txt"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {file_path}, found {len(lines)}."

    assert lines[0] == "defect_feature: vibration", f"First line of {file_path} is incorrect. Expected 'defect_feature: vibration', got '{lines[0]}'."
    assert lines[1] == "yield_feature: temperature", f"Second line of {file_path} is incorrect. Expected 'yield_feature: temperature', got '{lines[1]}'."

def test_metrics_file():
    """Verify that metrics.json exists, is valid JSON, and contains the correct metrics."""
    file_path = "/home/user/metrics.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    assert "classification_accuracy" in metrics, f"'classification_accuracy' key missing in {file_path}."
    assert "regression_mse" in metrics, f"'regression_mse' key missing in {file_path}."

    accuracy = metrics["classification_accuracy"]
    mse = metrics["regression_mse"]

    assert isinstance(accuracy, (int, float)), f"'classification_accuracy' must be a number, got {type(accuracy)}."
    assert isinstance(mse, (int, float)), f"'regression_mse' must be a number, got {type(mse)}."

    expected_accuracy = 0.815
    expected_mse = 22.8687

    assert math.isclose(accuracy, expected_accuracy, abs_tol=0.01), f"Classification accuracy {accuracy} is too far from expected {expected_accuracy}."
    assert math.isclose(mse, expected_mse, abs_tol=0.1), f"Regression MSE {mse} is too far from expected {expected_mse}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
