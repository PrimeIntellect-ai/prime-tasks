#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import numpy as np
import pytest
from PIL import Image

def generate_reference():
    raw_data = []
    for wid in range(1, 51):
        out = subprocess.check_output(['/app/hardware_sim', str(wid)], text=True)
        lines = out.strip().split('\n')
        data_lines = [l for l in lines if l and (l[0].isdigit() or (l[0] == '-' and l[1].isdigit()))]
        for l in data_lines:
            raw_data.append([float(x) for x in l.strip().split()])

    X = np.array(raw_data)

    # Standardize
    X_mean = np.mean(X, axis=0)
    X_std = np.std(X, axis=0, ddof=0)
    X_std[X_std == 0] = 1
    X_scaled = (X - X_mean) / X_std

    # SVD
    U, S, Vt = np.linalg.svd(X_scaled, full_matrices=False)

    variance_ratio = (S**2) / np.sum(S**2)
    cumulative_variance = np.cumsum(variance_ratio)
    k = np.argmax(cumulative_variance >= 0.95) + 1

    # Reconstruct
    X_recon = U[:, :k] @ np.diag(S[:k]) @ Vt[:k, :]
    return X_recon

def test_raw_data_exists():
    raw_data_path = "/home/user/raw_data.txt"
    assert os.path.exists(raw_data_path), f"File {raw_data_path} not found. Did you extract and concatenate the numerical data?"

def test_reconstructed_mse():
    student_file = '/home/user/reconstructed.csv'
    assert os.path.exists(student_file), f"File {student_file} not found. Did you save the reconstructed matrix?"

    try:
        student_recon = np.loadtxt(student_file, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load {student_file} as CSV: {e}")

    ref_recon = generate_reference()

    assert student_recon.shape == ref_recon.shape, f"Shape mismatch: expected {ref_recon.shape}, got {student_recon.shape}."

    mse = np.mean((student_recon - ref_recon)**2)
    assert mse <= 1e-4, f"MSE of reconstructed matrix is {mse}, which exceeds the threshold of 1e-4."

def test_pca_plot_exists_and_valid():
    plot_file = '/home/user/pca_plot.png'
    assert os.path.exists(plot_file), f"File {plot_file} not found. Did you save the PCA plot?"

    try:
        with Image.open(plot_file) as img:
            img.verify()
    except Exception as e:
        pytest.fail(f"File {plot_file} is not a valid image: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
