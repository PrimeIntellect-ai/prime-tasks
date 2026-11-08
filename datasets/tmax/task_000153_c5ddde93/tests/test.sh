#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pytest

def test_predictions_accuracy():
    preds_path = '/home/user/predictions.json'
    truth_path = '/tests/ground_truth.json'

    assert os.path.exists(preds_path), f"File {preds_path} does not exist. The script must generate it."
    assert os.path.exists(truth_path), f"File {truth_path} does not exist (should be provided with the tests)."

    with open(preds_path, 'r') as f:
        try:
            preds = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {preds_path} is not valid JSON.")

    with open(truth_path, 'r') as f:
        truth = json.load(f)

    assert isinstance(preds, list), f"Expected predictions to be a JSON array, got {type(preds).__name__}"
    assert len(preds) == len(truth), f"Length mismatch: predicted {len(preds)}, expected {len(truth)}"

    correct = sum(1 for p, t in zip(preds, truth) if p == t)
    accuracy = correct / len(truth)

    assert accuracy >= 1.0, f"Accuracy is {accuracy}, expected >= 1.0. Predictions: {preds}, Truth: {truth}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
