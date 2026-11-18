#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA

def test_reconstruction_mse():
    agent_file = '/home/user/reconstructed.csv'
    assert os.path.isfile(agent_file), f"Agent output file not found: {agent_file}"

    # Compute Golden Truth
    data = pd.read_csv('/app/data.csv')

    # Remove outliers based on image rules
    cleaned = data[(data['F2'] <= 10.0) | data['F2'].isna()]
    cleaned = cleaned[(cleaned['F4'] >= 0.0) | cleaned['F4'].isna()]

    # Impute with column mean
    imputed = cleaned.fillna(cleaned.mean())

    # PCA Reconstruction
    pca = PCA(n_components=2)
    transformed = pca.fit_transform(imputed)
    reconstructed_golden = pca.inverse_transform(transformed)

    # Read Agent Output
    try:
        agent_output = pd.read_csv(agent_file, header=None).values
    except Exception as e:
        assert False, f"Error reading agent output: {e}"

    assert agent_output.shape == reconstructed_golden.shape, \
        f"Shape mismatch: Expected {reconstructed_golden.shape}, got {agent_output.shape}"

    mse = np.mean((agent_output - reconstructed_golden) ** 2)

    assert mse <= 1e-4, f"MSE {mse} is greater than threshold 1e-4"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
