#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import requests
import numpy as np
import pytest

def test_deployed_model_exists():
    model_path = "/home/user/ml_pipeline/deploy/model.pkl"
    assert os.path.isfile(model_path), f"Deployed model not found at {model_path}"

def test_inference_api_accuracy():
    # Re-derive the metric as specified in the truth verifier script
    np.random.seed(999)
    X = np.random.randn(1000, 5) * [10, 1, 0.1, 100, 5]
    y = (X[:, 0] * 0.5 + X[:, 1] * 2.0 - X[:, 3] * 0.01 > 0).astype(int)

    correct = 0
    total = 1000

    for i in range(total):
        try:
            resp = requests.post(
                'http://localhost:5001/predict', 
                json={'features': X[i].tolist()},
                timeout=1
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get('prediction') == y[i]:
                    correct += 1
        except requests.exceptions.RequestException:
            pass

    accuracy = correct / total

    # The threshold is strictly greater than 0.82 according to the text, 
    # but the verifier condition says accuracy >= 0.82. We will use >= 0.82.
    assert accuracy >= 0.82, f"Accuracy metric failed: measured {accuracy}, expected >= 0.82"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
