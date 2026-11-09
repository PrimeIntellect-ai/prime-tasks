#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import h5py
import numpy as np
import pytest
from scipy.fft import fft, ifft, fftfreq
from scipy.stats import norm

SCRIPT_PATH = Path('/home/user/analyze.py')
DATA_DIR = Path('/home/user/data')
DATA_PATH = DATA_DIR / 'signal.h5'
RESULTS_DIR = Path('/home/user/results')
OUTPUT_PATH = RESULTS_DIR / 'output.h5'


def recreate_directory(path):
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


@pytest.fixture(scope='session', autouse=True)
def executed_submission():
    assert SCRIPT_PATH.exists(), f'Expected script {SCRIPT_PATH} does not exist.'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_PATH} must be a regular file.'
    assert SCRIPT_PATH.stat().st_size > 0, f'{SCRIPT_PATH} is empty.'

    # Install a fresh, verifier-generated 1000-sample input immediately before
    # execution so an agent cannot weaken verification by replacing the input.
    recreate_directory(DATA_DIR)
    recreate_directory(RESULTS_DIR)

    seed = int.from_bytes(os.urandom(8), 'little')
    rng = np.random.default_rng(seed)
    t = np.linspace(0, 1, 1000, endpoint=False)
    raw_signal = (
        0.9 * np.sin(2 * np.pi * 10 * t + rng.uniform(-np.pi, np.pi))
        + 0.45 * np.sin(2 * np.pi * 25 * t + rng.uniform(-np.pi, np.pi))
        + 0.2 * np.sin(2 * np.pi * 125 * t + rng.uniform(-np.pi, np.pi))
        + rng.normal(0, 0.2, 1000)
    )

    with h5py.File(DATA_PATH, 'w') as f:
        f.create_dataset('raw_signal', data=raw_signal)

    n = len(raw_signal)
    freqs = fftfreq(n, d=1/1000)
    fft_vals = fft(raw_signal)
    fft_vals[np.abs(freqs) > 50] = 0
    expected_smoothed = np.real(ifft(fft_vals))

    residual = raw_signal - expected_smoothed
    expected_mu, expected_sigma = norm.fit(residual)

    perturb_rng = np.random.RandomState(42)
    perturbations = perturb_rng.uniform(-1e-6, 1e-6, size=(50, n))
    sigmas = []
    for perturbation in perturbations:
        p_sig = raw_signal + perturbation
        p_fft_vals = fft(p_sig)
        p_fft_vals[np.abs(freqs) > 50] = 0
        p_smoothed = np.real(ifft(p_fft_vals))
        _, p_sigma = norm.fit(p_sig - p_smoothed)
        sigmas.append(p_sigma)
    expected_stability_std = np.std(sigmas, ddof=0)

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'analyze.py failed with exit code {result.returncode}:\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )

    return expected_smoothed, expected_mu, expected_sigma, expected_stability_std


def test_output_file_exists(executed_submission):
    assert OUTPUT_PATH.exists(), f'Expected output file {OUTPUT_PATH} does not exist.'
    assert OUTPUT_PATH.is_file(), f'Path {OUTPUT_PATH} is not a file.'


def test_output_contents_and_accuracy(executed_submission):
    expected_smoothed, expected_mu, expected_sigma, expected_stability_std = executed_submission

    try:
        with h5py.File(OUTPUT_PATH, 'r') as f:
            assert 'smoothed_signal' in f, "Dataset 'smoothed_signal' missing"
            assert 'noise_params' in f, "Dataset 'noise_params' missing"
            assert 'stability_std' in f, "Dataset 'stability_std' missing"

            out_smoothed = f['smoothed_signal'][:]
            out_noise = f['noise_params'][:]
            out_std_ds = f['stability_std']
            out_std = out_std_ds[()] if out_std_ds.shape == () else out_std_ds[0]
    except Exception as e:
        pytest.fail(f'Failed to read output file or missing datasets: {e}')

    assert np.allclose(out_smoothed, expected_smoothed, atol=1e-5), \
        'smoothed_signal values do not match expected results within tolerance.'
    assert np.allclose(out_noise, [expected_mu, expected_sigma], atol=1e-5), \
        f'noise_params mismatch. Expected {[expected_mu, expected_sigma]}, got {out_noise}'
    assert np.isclose(out_std, expected_stability_std, atol=1e-9), \
        f'stability_std mismatch. Expected {expected_stability_std}, got {out_std}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
