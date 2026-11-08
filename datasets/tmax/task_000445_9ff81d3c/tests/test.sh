#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random

def test_model_weights_exist():
    weights_path = "/home/user/model_weights.json"
    assert os.path.isfile(weights_path), f"Output file {weights_path} is missing. Did you save the model weights?"

def test_model_weights_format():
    weights_path = "/home/user/model_weights.json"
    if not os.path.isfile(weights_path):
        return # Handled by previous test

    with open(weights_path, "r") as f:
        try:
            weights = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {weights_path} is not valid JSON."

    required_keys = ["beta_0", "beta_1", "beta_2"]
    for key in required_keys:
        assert key in weights, f"Key '{key}' is missing from {weights_path}"
        assert isinstance(weights[key], (int, float)), f"Value for '{key}' must be a number."

def test_model_accuracy_mae():
    weights_path = "/home/user/model_weights.json"
    if not os.path.isfile(weights_path):
        return # Handled by previous test

    with open(weights_path, "r") as f:
        try:
            weights = json.load(f)
        except json.JSONDecodeError:
            return # Handled by previous test

    try:
        b0 = float(weights['beta_0'])
        b1 = float(weights['beta_1'])
        b2 = float(weights['beta_2'])
    except (KeyError, ValueError):
        return # Handled by previous test

    mae_sum = 0
    test_n = 1000
    random.seed(42) # Fixed seed for deterministic evaluation

    for _ in range(test_n):
        L = random.randint(18, 30)
        GC = random.randint(5, L)

        # True underlying relationship
        true_tm = 22.0 + 0.3 * L + 1.2 * GC

        # Predicted relationship from agent's model
        pred_tm = b0 + b1 * L + b2 * GC

        mae_sum += abs(true_tm - pred_tm)

    mae = mae_sum / test_n

    assert mae <= 0.5, f"Model MAE is {mae:.4f}, which exceeds the maximum allowed threshold of 0.5. Your weights: beta_0={b0}, beta_1={b1}, beta_2={b2}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
