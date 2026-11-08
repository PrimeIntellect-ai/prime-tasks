#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import numpy as np
from scipy.io import wavfile

def test_clean_audio_exists_and_mse():
    input_path = '/app/intercept.wav'
    test_path = '/home/user/clean_audio.wav'

    assert os.path.exists(test_path), f"Expected output file not found at {test_path}"
    assert os.path.exists(input_path), f"Input file not found at {input_path}"

    try:
        sr1, input_data = wavfile.read(input_path)
    except Exception as e:
        pytest.fail(f"Failed to read input file: {e}")

    expected = input_data.copy()
    expected[44100:88201] = 0

    try:
        sr2, data2 = wavfile.read(test_path)
    except Exception as e:
        pytest.fail(f"Failed to read test file: {e}")

    assert sr1 == sr2, f"Sample rate mismatch: expected {sr1}, got {sr2}"
    assert len(expected) == len(data2), f"Length mismatch: expected {len(expected)} samples, got {len(data2)} samples"

    mse = np.mean((expected.astype(float) - data2.astype(float))**2)
    assert mse < 0.1, f"MSE too high: {mse} >= 0.1. The audio was not correctly redacted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
