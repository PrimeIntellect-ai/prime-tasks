#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import numpy as np
import pytest

HOME = '/home/user'
SOURCE = os.path.join(HOME, 'process.go')
MODULE = os.path.join(HOME, 'go.mod')
SPECTRA = os.path.join(HOME, 'spectra.csv')
RESULTS = os.path.join(HOME, 'results.json')
BINARY = '/tmp/submission_process'


def test_go_source_exists():
    """Verify that the Go source file was created."""
    assert os.path.exists(SOURCE), f"Go source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"Path {SOURCE} is not a file."


def test_go_module_initialized():
    """Verify that a Go module was initialized."""
    assert os.path.exists(MODULE), "Go module was not initialized. Missing /home/user/go.mod"


@pytest.fixture(scope='session')
def compiled_program():
    proc = subprocess.run(
        ['go', 'build', '-o', BINARY, SOURCE],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"process.go did not compile:\n{proc.stdout}"
    assert os.path.isfile(BINARY), "Go build did not produce an executable"
    return BINARY


def expected_for(data):
    assert data.shape == (100, 50)
    centered = data - np.mean(data, axis=0)
    u, singular_values, vt = np.linalg.svd(centered, full_matrices=False)
    energy = singular_values * singular_values
    threshold = 0.95 * np.sum(energy)
    k = int(np.searchsorted(np.cumsum(energy), threshold, side='left') + 1)
    reconstructed = (u[:, :k] * singular_values[:k]) @ vt[:k, :]
    residual = centered - reconstructed
    return k, float(np.mean(residual)), float(np.std(residual, ddof=0))


def run_and_read(binary):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        [binary],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"Compiled program failed:\n{proc.stdout}"
    assert os.path.exists(RESULTS), "The executed Go program did not create /home/user/results.json"
    with open(RESULTS, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {RESULTS} is not valid JSON: {exc}")
    return result


def assert_matches(result, expected):
    expected_keys = {'k', 'residual_mean', 'residual_std'}
    missing_keys = expected_keys - set(result.keys())
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"
    assert isinstance(result['k'], int) and not isinstance(result['k'], bool), \
        f"Expected 'k' to be an integer, got {type(result['k']).__name__}"
    assert isinstance(result['residual_mean'], (int, float)) and not isinstance(result['residual_mean'], bool), \
        "Expected 'residual_mean' to be a float"
    assert isinstance(result['residual_std'], (int, float)) and not isinstance(result['residual_std'], bool), \
        "Expected 'residual_std' to be a float"
    assert math.isfinite(result['residual_mean'])
    assert math.isfinite(result['residual_std'])
    expected_k, expected_mean, expected_std = expected
    assert result['k'] == expected_k, f"Expected k={expected_k}, got {result['k']}"
    assert math.isclose(result['residual_mean'], expected_mean, rel_tol=1e-6, abs_tol=2e-6), \
        f"Expected residual_mean={expected_mean}, got {result['residual_mean']}"
    assert math.isclose(result['residual_std'], expected_std, rel_tol=2e-5, abs_tol=2e-6), \
        f"Expected residual_std={expected_std}, got {result['residual_std']}"


def test_program_computes_results_on_derived_input(compiled_program):
    """Execute the submitted program on an unanticipated 100x50 matrix."""
    with open(SPECTRA, 'rb') as f:
        original = f.read()
    try:
        seed = int.from_bytes(os.urandom(16), 'big')
        rng = np.random.default_rng(seed)
        data = rng.normal(size=(100, 50))
        data += (rng.normal(size=(100, 6)) @ rng.normal(size=(6, 50))) * 0.35
        np.savetxt(SPECTRA, data, delimiter=',', fmt='%.9f')
        exact_input = np.loadtxt(SPECTRA, delimiter=',')
        assert_matches(run_and_read(compiled_program), expected_for(exact_input))
    finally:
        with open(SPECTRA, 'wb') as f:
            f.write(original)


def test_results_json_exists_and_valid(compiled_program):
    """Run the program on the supplied data and check its structure and values."""
    original_data = np.loadtxt(SPECTRA, delimiter=',')
    results = run_and_read(compiled_program)
    assert_matches(results, expected_for(original_data))

    # Preserve the original verifier's dataset-specific assertions.
    assert results['k'] == 3, f"Expected k=3 based on the dataset's intrinsic rank, but got {results['k']}"
    assert abs(results['residual_mean']) < 1e-4, \
        f"Expected residual_mean close to 0, got {results['residual_mean']}"
    assert 0.45 < results['residual_std'] < 0.55, \
        f"Expected residual_std to be around 0.5, got {results['residual_std']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
