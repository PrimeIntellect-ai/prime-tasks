#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_centrality_json_exists():
    output_file_path = "/home/user/centrality.json"
    assert os.path.exists(output_file_path), f"Output file does not exist: {output_file_path}"
    assert os.path.isfile(output_file_path), f"Path is not a file: {output_file_path}"

def test_centrality_pagerank_mse():
    output_file_path = "/home/user/centrality.json"

    with open(output_file_path, 'r') as f:
        try:
            pred = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/centrality.json is not valid JSON.")

    assert isinstance(pred, dict), "The JSON should be a dictionary."

    truth = {
        'Socrates': 0.06451613093282276, 
        'Plato': 0.2290322648165207, 
        'Aristotle': 0.2591935560268654, 
        'Alexander': 0.28483065355565825, 
        'Pythagoras': 0.06451613093282276, 
        'Heraclitus': 0.06451613093282276
    }

    mse = 0.0
    for key, true_val in truth.items():
        pred_val = pred.get(key, 0.0)
        try:
            pred_val = float(pred_val)
        except ValueError:
            pytest.fail(f"Value for {key} is not a float: {pred_val}")
        mse += (pred_val - true_val)**2

    mse /= len(truth)

    threshold = 0.0001
    assert mse <= threshold, f"MSE {mse} exceeds the threshold of {threshold}. Predicted values: {pred}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
