#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np


def test_weights_file_exists():
    file_path = "/home/user/weights.txt"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. The task requires generating this file."


def test_weights_file_content():
    actual_file = "/home/user/weights.txt"
    assert os.path.isfile(actual_file), f"Output file {actual_file} is missing."

    signals = np.loadtxt("/home/user/signals.csv", delimiter=",")
    target = np.loadtxt("/home/user/target.csv", delimiter=",").reshape(-1)

    assert signals.shape == (1000, 50), f"Unexpected signals shape: {signals.shape}."
    assert target.shape == (1000,), f"Unexpected target shape: {target.shape}."

    freqs = np.fft.fftfreq(1000)
    filtered = np.empty_like(signals, dtype=float)
    for i in range(50):
        coefficients = np.fft.fft(signals[:, i])
        coefficients[np.abs(freqs) > 0.1] = 0
        filtered[:, i] = np.fft.ifft(coefficients).real

    U, S, Vt = np.linalg.svd(filtered, full_matrices=False)
    features = U[:, :3] * S[:3]
    expected_weights, _, _, _ = np.linalg.lstsq(features, target, rcond=None)
    expected_content = ",".join(f"{weight:.6f}" for weight in expected_weights)

    with open(actual_file, "r") as f:
        actual_content = f.read().strip()

    assert expected_content, "Expected content is empty."
    assert actual_content, "Actual content is empty."

    expected_parts = expected_content.split(",")
    actual_parts = actual_content.split(",")
    assert len(actual_parts) == 3, f"Expected 3 weights separated by commas, found {len(actual_parts)}."

    for i, (expected, actual) in enumerate(zip(expected_parts, actual_parts)):
        assert actual == expected, f"Weight at index {i} does not match. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
