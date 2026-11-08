#!/bin/bash
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
export PATH="/opt/rust/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import numpy as np
import pytest

SIM_DIR = Path('/app/diffusion_sim')
ANALYZER_DIR = Path('/home/user/analyzer')
FINAL_PATH = Path('/home/user/final_state.json')
SPECTRUM_PATH = Path('/home/user/spectrum.json')
N = 256


def run_cargo(project):
    result = subprocess.run(
        ['cargo', 'run', '--offline', '--quiet'],
        cwd=str(project),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f'cargo run failed in {project}:\n{result.stdout}'


def load_array(path, expected_len=N):
    assert path.is_file(), f'File {path} does not exist.'
    try:
        with path.open() as f:
            value = json.load(f)
        array = np.asarray(value, dtype=float)
    except Exception as exc:
        pytest.fail(f'Could not load {path} as a JSON array of floats: {exc}')
    assert array.ndim == 1, f'{path} must contain a one-dimensional JSON array.'
    assert len(array) == expected_len, f'Expected {expected_len} elements in {path}, got {len(array)}.'
    assert np.all(np.isfinite(array)), f'{path} contains non-finite values.'
    return array


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_pipeline():
    for project in (SIM_DIR, ANALYZER_DIR):
        assert (project / 'Cargo.toml').is_file(), f'Missing Rust manifest: {project / "Cargo.toml"}'
        assert (project / 'src' / 'main.rs').is_file(), f'Missing Rust source: {project / "src" / "main.rs"}'

    # Remove precomputed artifacts and require the submitted simulator to recreate its output.
    FINAL_PATH.unlink(missing_ok=True)
    SPECTRUM_PATH.unlink(missing_ok=True)
    run_cargo(SIM_DIR)

    final_state = load_array(FINAL_PATH)
    x = 2.0 * np.pi * np.arange(N) / N
    expected_state = np.exp(-0.1) * np.sin(x) + 0.5 * np.exp(-0.9) * np.sin(3.0 * x)
    max_state_error = np.max(np.abs(final_state - expected_state))
    assert max_state_error < 2e-4, (
        f'Simulator output does not solve the requested heat equation; maximum error is {max_state_error}.'
    )

    # Exercise the analyzer on unpredictable inputs. This rejects a fixed, precomputed spectrum.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
    probes = [
        rng.normal(size=N),
        rng.normal(size=N) + 0.3 * np.sin(7.0 * x) - 0.2 * np.cos(19.0 * x),
    ]
    for probe in probes:
        with FINAL_PATH.open('w') as f:
            json.dump(probe.tolist(), f)
        SPECTRUM_PATH.unlink(missing_ok=True)
        run_cargo(ANALYZER_DIR)
        actual = load_array(SPECTRUM_PATH)
        expected = np.abs(np.fft.fft(probe)) ** 2 / (N ** 2)
        assert np.allclose(actual, expected, rtol=1e-8, atol=1e-9), (
            'Analyzer PSD does not match a forward FFT with 1/N^2 normalization on a verifier-generated input.'
        )

    # Recreate the exact requested end-to-end artifacts for the original assertions below.
    FINAL_PATH.unlink(missing_ok=True)
    SPECTRUM_PATH.unlink(missing_ok=True)
    run_cargo(SIM_DIR)
    run_cargo(ANALYZER_DIR)


def test_spectrum_json_exists():
    path = '/home/user/spectrum.json'
    assert os.path.isfile(path), f"File {path} does not exist. The analyzer should output the PSD here."


def test_spectrum_mse():
    path = '/home/user/spectrum.json'
    assert os.path.isfile(path), f"File {path} missing."

    with open(path, 'r') as f:
        try:
            agent_psd = np.array(json.load(f), dtype=float)
        except Exception as e:
            pytest.fail(f"Could not load {path} as a JSON array of floats: {e}")

    assert len(agent_psd) == N, f"Expected {N} elements in PSD array, but got {len(agent_psd)}."
    assert np.all(np.isfinite(agent_psd)), 'PSD contains non-finite values.'

    exact_psd = np.zeros(N)
    exact_psd[1] = 0.25 * np.exp(-0.2)
    exact_psd[-1] = 0.25 * np.exp(-0.2)
    exact_psd[3] = 0.0625 * np.exp(-1.8)
    exact_psd[-3] = 0.0625 * np.exp(-1.8)

    mse = np.mean((agent_psd - exact_psd)**2)
    threshold = 1e-4
    assert mse < threshold, f"MSE {mse} is not below the threshold {threshold}. The computed PSD does not match the theoretical expected PSD."

    # Also require the nonzero Fourier modes individually, avoiding dilution over 256 bins.
    assert np.max(np.abs(agent_psd - exact_psd)) < 2e-5, 'PSD bins do not closely match the analytical spectrum.'


def test_final_state_json_exists():
    path = '/home/user/final_state.json'
    assert os.path.isfile(path), f"File {path} does not exist. The simulator should output the final spatial array here."


def test_final_state_contents():
    actual = load_array(FINAL_PATH)
    x = 2.0 * np.pi * np.arange(N) / N
    expected = np.exp(-0.1) * np.sin(x) + 0.5 * np.exp(-0.9) * np.sin(3.0 * x)
    assert np.max(np.abs(actual - expected)) < 2e-4
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
