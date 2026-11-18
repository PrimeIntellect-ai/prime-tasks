#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import tempfile
import numpy as np
import h5py
import pytest

def test_wave_data_exists():
    assert os.path.exists('/home/user/wave_data.bin'), "/home/user/wave_data.bin is missing. Did you run the simulator?"

def test_wave_data_matches_simulator():
    data_path = '/home/user/wave_data.bin'
    assert os.path.exists(data_path), f"Missing {data_path}"
    assert os.path.isfile('/app/wave_sim'), "/app/wave_sim is missing"
    assert os.access('/app/wave_sim', os.X_OK), "/app/wave_sim is not executable"

    with tempfile.TemporaryDirectory(prefix='wave_verify_') as tmpdir:
        reference_path = os.path.join(tmpdir, 'wave_data.bin')
        subprocess.run(
            ['/app/wave_sim', '64', '64', '512', reference_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with open(reference_path, 'rb') as f:
            reference_data = f.read()
        with open(data_path, 'rb') as f:
            agent_data = f.read()

    assert agent_data == reference_data, (
        "/home/user/wave_data.bin does not match the output produced by "
        "'/app/wave_sim 64 64 512 /home/user/wave_data.bin'"
    )

def test_results_exists():
    assert os.path.exists('/home/user/results.h5'), "/home/user/results.h5 is missing. Did you export the results?"

def test_svd_accuracy():
    data_path = '/home/user/wave_data.bin'
    assert os.path.exists(data_path), f"Missing {data_path}"

    # Read and reshape the raw binary data
    data = np.fromfile(data_path, dtype=np.float32)
    nx, ny, nt = 64, 64, 512
    assert data.size == nx * ny * nt, f"Expected {nx*ny*nt} floats in {data_path}, got {data.size}"
    data = data.reshape((nx, ny, nt))

    # Perform FFT along the time axis
    fft_data = np.fft.fft(data, axis=2)

    # Find the peak frequency index (ignoring DC component)
    energy = np.sum(np.abs(fft_data)**2, axis=(0, 1))
    energy[0] = 0
    k_peak = np.argmax(energy[:nt//2])

    # Extract the complex matrix at the peak frequency and compute SVD
    matrix = fft_data[:, :, k_peak]
    _, S, _ = np.linalg.svd(matrix)
    truth_svals = S[:3]

    # Read the agent's output
    results_path = '/home/user/results.h5'
    assert os.path.exists(results_path), f"Missing {results_path}"

    try:
        with h5py.File(results_path, 'r') as f:
            assert '/top_svals' in f, "Dataset '/top_svals' not found in HDF5 file."
            agent_svals = np.array(f['/top_svals'])
    except Exception as e:
        pytest.fail(f"Failed to read {results_path}: {e}")

    assert agent_svals.shape == (3,) or agent_svals.shape == (3, 1) or len(agent_svals) == 3, \
        f"Expected 3 singular values, got shape {agent_svals.shape}"

    agent_svals = agent_svals.flatten()

    # Compute metric
    error = np.max(np.abs(truth_svals - agent_svals))
    threshold = 1e-3

    assert error <= threshold, (
        f"Max absolute error {error} exceeds threshold {threshold}.\n"
        f"Truth SVD values: {truth_svals}\n"
        f"Agent SVD values: {agent_svals}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
