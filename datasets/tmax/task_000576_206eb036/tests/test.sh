#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_run_metrics_exists_and_correct():
    metrics_path = "/home/user/run_metrics.json"
    assert os.path.exists(metrics_path), f"The metrics file {metrics_path} is missing."
    assert os.path.isfile(metrics_path), f"The path {metrics_path} is not a file."

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {metrics_path} does not contain valid JSON."

    assert "variance_explained" in metrics, "The key 'variance_explained' is missing from the JSON."
    assert "accuracy" in metrics, "The key 'accuracy' is missing from the JSON."

    expected_variance = 0.6973
    expected_accuracy = 0.8165

    actual_variance = metrics["variance_explained"]
    actual_accuracy = metrics["accuracy"]

    assert isinstance(actual_variance, float), f"Expected 'variance_explained' to be a float, got {type(actual_variance).__name__}."
    assert isinstance(actual_accuracy, float), f"Expected 'accuracy' to be a float, got {type(actual_accuracy).__name__}."

    # Compare rounded values just in case
    assert round(actual_variance, 4) == expected_variance, f"Expected variance_explained to be {expected_variance}, got {actual_variance}."
    assert round(actual_accuracy, 4) == expected_accuracy, f"Expected accuracy to be {expected_accuracy}, got {actual_accuracy}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
