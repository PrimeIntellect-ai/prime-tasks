#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import sys
import os
import numpy as np
import pytest

def test_feature_extractor_mse():
    module_path = "/home/user/reconstructed_pipeline.py"
    assert os.path.isfile(module_path), f"File not found: {module_path}"

    sys.path.insert(0, "/home/user")
    try:
        from reconstructed_pipeline import FeatureExtractor
    except ImportError as e:
        pytest.fail(f"Could not import FeatureExtractor from reconstructed_pipeline: {e}")

    # Ground truth parameters used to compile the binary
    np.random.seed(42)
    W_true = np.random.randn(50, 5)
    b_true = np.random.randn(5)

    # Generate test data
    X_test = np.random.randn(10000, 50)
    Y_expected = X_test @ W_true + b_true

    try:
        model = FeatureExtractor()
        Y_pred = model.transform(X_test)
    except Exception as e:
        pytest.fail(f"Error during model initialization or transform: {e}")

    assert isinstance(Y_pred, np.ndarray), "transform() must return a NumPy array"
    assert Y_pred.shape == Y_expected.shape, f"Expected shape {Y_expected.shape}, got {Y_pred.shape}"

    mse = np.mean((Y_expected - Y_pred) ** 2)
    assert mse <= 0.005, f"MSE is {mse:.6f}, which is greater than the threshold of 0.005"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
