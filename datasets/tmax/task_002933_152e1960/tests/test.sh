#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import joblib
import numpy as np
from sklearn.metrics import mean_squared_error

def test_model_exists():
    """Check if the trained model was saved to the correct path."""
    model_path = '/home/user/model.joblib'
    assert os.path.isfile(model_path), f"The model file {model_path} is missing. Did you save it using joblib?"

def test_model_performance():
    """Evaluate the saved model on the hidden test set to ensure MSE <= 2.5."""
    model_path = '/home/user/model.joblib'
    assert os.path.isfile(model_path), "Model file not found."

    try:
        model = joblib.load(model_path)
    except Exception as e:
        pytest.fail(f"Failed to load the model from {model_path}. Error: {e}")

    embeddings_path = '/tests/hidden_test_embeddings.npy'
    targets_path = '/tests/hidden_test_targets.npy'

    assert os.path.isfile(embeddings_path), f"Hidden test embeddings missing at {embeddings_path}."
    assert os.path.isfile(targets_path), f"Hidden test targets missing at {targets_path}."

    X_test = np.load(embeddings_path)
    y_test = np.load(targets_path)

    try:
        predictions = model.predict(X_test)
    except Exception as e:
        pytest.fail(f"Model failed to predict on the test embeddings. Error: {e}")

    mse = mean_squared_error(y_test, predictions)
    assert mse <= 2.5, f"Model performance did not meet the threshold. Expected MSE <= 2.5, but got {mse:.4f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
