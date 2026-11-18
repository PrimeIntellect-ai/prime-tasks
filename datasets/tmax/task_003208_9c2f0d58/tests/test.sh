#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
from scipy.io import wavfile
import pytest

def test_clean_data_exists():
    """Test that the agent saved the output file at the correct location."""
    expected_path = '/home/user/clean_data.wav'
    assert os.path.isfile(expected_path), f"The output file is missing at {expected_path}"

def test_clean_data_format_and_metric():
    """Test that the output file is a valid WAV file, has correct sample rate, and meets the MSE threshold."""
    output_path = '/home/user/clean_data.wav'
    truth_path = '/tests/expected_clean.wav'

    assert os.path.isfile(output_path), f"Output file not found: {output_path}"
    assert os.path.isfile(truth_path), f"Truth file not found: {truth_path}"

    try:
        rate1, data1 = wavfile.read(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as a WAV file: {e}")

    try:
        rate2, data2 = wavfile.read(truth_path)
    except Exception as e:
        pytest.fail(f"Failed to read {truth_path} as a WAV file: {e}")

    assert rate1 == 16000, f"Expected sample rate of 16000 Hz, but got {rate1} Hz."
    assert rate1 == rate2, "Sample rates do not match."

    assert len(data1) == len(data2), f"Expected length {len(data2)}, but got {len(data1)}."

    # Normalize to [-1, 1] for comparison
    data1_float = data1.astype(np.float32) / 32767.0
    data2_float = data2.astype(np.float32) / 32767.0

    mse = np.mean((data1_float - data2_float)**2)
    threshold = 1e-5

    assert mse < threshold, f"MSE of {mse:.2e} exceeds the maximum allowed threshold of {threshold:.2e}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
