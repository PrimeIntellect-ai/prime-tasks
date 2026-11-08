#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_prediction_accuracy():
    target_value = 1.44
    threshold = 0.05
    prediction_file = "/home/user/prediction.txt"

    assert os.path.exists(prediction_file), f"Verification Failed: {prediction_file} not found"
    assert os.path.isfile(prediction_file), f"Verification Failed: {prediction_file} is not a file"

    with open(prediction_file, "r") as f:
        content = f.read().strip()

    try:
        pred = float(content)
    except ValueError:
        pytest.fail(f"Verification Failed: Could not parse float from file. Content: '{content}'")

    error = abs(pred - target_value)
    assert error <= threshold, f"Verification Failed: Predicted value {pred} has error {error}, which is greater than threshold {threshold} (target: {target_value})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
