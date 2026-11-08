#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
from scipy.io import wavfile

SERVICE_DIR = '/home/user/aero_service'
SOURCE_PATH = os.path.join(SERVICE_DIR, 'aero_decoder.cpp')
BINARY_PATH = os.path.join(SERVICE_DIR, 'aero_decoder')
INPUT_PATH = '/app/blackbox_audio.wav'
OUTPUT_PATH = '/home/user/output_reconstructed.wav'
REFERENCE_PATH = '/tests/reference_clean.wav'


def calculate_mse(file1, file2):
    rate1, data1 = wavfile.read(file1)
    rate2, data2 = wavfile.read(file2)

    if rate1 != rate2 or data1.shape != data2.shape or data1.size == 0:
        return float('inf')

    d1 = data1.astype(np.float64)
    d2 = data2.astype(np.float64)

    d1 = d1 / np.max(np.abs(d1)) if np.max(np.abs(d1)) > 0 else d1
    d2 = d2 / np.max(np.abs(d2)) if np.max(np.abs(d2)) > 0 else d2
    return np.mean((d1 - d2) ** 2)


def test_reconstructed_audio_mse():
    assert os.path.isfile(SOURCE_PATH), f'Source file {SOURCE_PATH} is missing.'
    assert os.path.isfile(INPUT_PATH), f'Input file {INPUT_PATH} is missing.'
    assert os.path.isfile(REFERENCE_PATH), f'Reference file {REFERENCE_PATH} is missing.'

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)

    build = subprocess.run(
        ['make'], cwd=SERVICE_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert build.returncode == 0, f'make failed:\n{build.stdout}'
    assert os.path.isfile(BINARY_PATH), 'make did not produce aero_decoder.'
    with open(BINARY_PATH, 'rb') as binary_file:
        assert binary_file.read(4) == b'\x7fELF', 'aero_decoder is not an ELF executable.'

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    run = subprocess.run(
        [BINARY_PATH, INPUT_PATH, OUTPUT_PATH], cwd=SERVICE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert run.returncode == 0, f'aero_decoder failed with exit code {run.returncode}:\n{run.stdout}'
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist. Did the service generate it?'

    try:
        mse = calculate_mse(OUTPUT_PATH, REFERENCE_PATH)
    except Exception as exc:
        assert False, f'Failed to compute MSE. Ensure {OUTPUT_PATH} is a valid WAV file. Error: {exc}'

    threshold = 0.01
    assert mse < threshold, f'Reconstructed audio MSE is {mse:.6f}, which is not less than the threshold {threshold}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
