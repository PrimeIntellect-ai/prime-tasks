#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest

PROJECT = Path('/home/user/spectra_optimizer')
RESULT = Path('/home/user/result.json')
SIGNAL = Path('/home/user/data/signal.bin')
N = 1_000_000


def load_result():
    assert RESULT.is_file(), f'The result file is missing at {RESULT}'
    try:
        with RESULT.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file {RESULT} does not contain valid JSON.')

    required_keys = {'k_max', 's_max', 'best_alpha', 'min_error'}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f'Missing required keys in result.json: {missing_keys}'
    return data


def oracle(y):
    assert y.dtype == np.float32 and y.size == N

    # Accumulate in f64 to evaluate the mathematical moving-average definition.
    prefix = np.empty(N + 1, dtype=np.float64)
    prefix[0] = 0.0
    np.cumsum(y, dtype=np.float64, out=prefix[1:])
    s = np.zeros(N, dtype=np.float64)
    s[5:N-5] = (prefix[11:] - prefix[:-11]) / 11.0

    k_max = int(np.argmax(s))
    s_max = float(s[k_max])
    assert 50 <= k_max < N - 50
    observed = s[k_max-50:k_max+51]
    j2 = np.arange(-50, 51, dtype=np.float64) ** 2

    best_i = 0
    best_error = float('inf')
    # Evaluate every one of the specified one million candidates, in chunks.
    for start in range(0, 1_000_000, 20_000):
        stop = min(start + 20_000, 1_000_000)
        indices = np.arange(start, stop, dtype=np.float64)
        alpha = 0.1 + indices * (9.9 / 999999.0)
        model = s_max * np.exp(-j2[None, :] / (alpha[:, None] ** 2))
        errors = np.sum((observed[None, :] - model) ** 2, axis=1)
        local = int(np.argmin(errors))
        value = float(errors[local])
        if value < best_error:
            best_error = value
            best_i = start + local

    best_alpha = 0.1 + best_i * (9.9 / 999999.0)
    return {
        'k_max': k_max,
        's_max': round(s_max, 4),
        'best_alpha': round(best_alpha, 4),
        'min_error': round(best_error, 4),
    }


def assert_matches(data, expected):
    for key in ('s_max', 'best_alpha', 'min_error'):
        assert isinstance(data[key], (int, float)), f'{key} must be a number'
        assert math.isfinite(float(data[key])), f'{key} must be finite'
    assert data['k_max'] == expected['k_max'], (
        f"Expected k_max={expected['k_max']}, got {data.get('k_max')}"
    )
    assert abs(float(data['s_max']) - expected['s_max']) <= 0.002, (
        f"Incorrect s_max: expected {expected['s_max']}, got {data['s_max']}"
    )
    assert abs(float(data['best_alpha']) - expected['best_alpha']) <= 0.003, (
        f"Incorrect best_alpha: expected {expected['best_alpha']}, got {data['best_alpha']}"
    )
    assert abs(float(data['min_error']) - expected['min_error']) <= 0.01, (
        f"Incorrect min_error: expected {expected['min_error']}, got {data['min_error']}"
    )


def test_project_release_binary_and_computation():
    assert PROJECT.is_dir(), 'Cargo project /home/user/spectra_optimizer is missing'
    manifest = PROJECT / 'Cargo.toml'
    source_dir = PROJECT / 'src'
    assert manifest.is_file(), 'Cargo.toml is missing'
    assert source_dir.is_dir(), 'Cargo src directory is missing'

    manifest_text = manifest.read_text(errors='replace')
    assert re.search(r'(?m)^\s*rayon\s*=', manifest_text), 'Cargo.toml must depend on rayon'
    rust_files = list(source_dir.rglob('*.rs'))
    assert rust_files, 'The Cargo project contains no Rust source files'
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files)
    assert re.search(r'(into_par_iter|par_iter|par_bridge|rayon::scope|rayon::join|scope_fifo|spawn_fifo)', source), (
        'Rust source does not use a Rayon parallel construct for the grid search'
    )

    metadata_run = subprocess.run(
        ['cargo', 'metadata', '--format-version=1', '--no-deps'],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert metadata_run.returncode == 0, f'Invalid Cargo project: {metadata_run.stderr}'
    metadata = json.loads(metadata_run.stdout)
    package = next((p for p in metadata['packages'] if Path(p['manifest_path']) == manifest), None)
    assert package is not None
    bins = [t['name'] for t in package['targets'] if 'bin' in t['kind']]
    assert bins, 'Cargo project has no binary target'
    binary = PROJECT / 'target' / 'release' / bins[0]
    assert binary.is_file() and os.access(binary, os.X_OK), 'Release-mode executable is missing'
    assert binary.read_bytes()[:4] == b'\x7fELF', 'Release artifact is not a native executable'
    newest_input = max([manifest.stat().st_mtime] + [p.stat().st_mtime for p in rust_files])
    assert binary.stat().st_mtime >= newest_input, 'Release executable is older than the project sources'

    original_signal = SIGNAL.read_bytes()
    original_result = RESULT.read_bytes() if RESULT.exists() else None
    assert len(original_signal) == N * 4, 'signal.bin has the wrong size'

    try:
        original_y = np.frombuffer(original_signal, dtype='<f4')
        expected_original = oracle(original_y)
        if RESULT.exists():
            RESULT.unlink()
        run = subprocess.run([str(binary)], cwd=PROJECT, text=True, capture_output=True, timeout=180)
        assert run.returncode == 0, f'Release executable failed: {run.stderr}'
        data = load_result()

        # Preserve the verifier's original assertions.
        assert data['k_max'] == 500000, f"Expected k_max=500000, got {data.get('k_max')}"
        best_alpha = data['best_alpha']
        assert isinstance(best_alpha, (int, float)), 'best_alpha must be a number'
        assert 4.0 < best_alpha < 5.5, f'best_alpha {best_alpha} is out of expected bounds (4.0, 5.5)'
        assert isinstance(data['s_max'], (int, float)), 's_max must be a number'
        assert isinstance(data['min_error'], (int, float)), 'min_error must be a number'
        assert_matches(data, expected_original)
        valid_original_result = RESULT.read_bytes()

        # Exercise the built artifact on a second, verifier-generated spectrum so
        # fixed result.json values cannot pass.
        x = np.arange(N, dtype=np.float64)
        alternate = (9.0 * np.exp(-((x - 345678.0) ** 2) / (7.2 ** 2))).astype('<f4')
        SIGNAL.write_bytes(alternate.tobytes())
        expected_alternate = oracle(alternate)
        RESULT.unlink()
        run = subprocess.run([str(binary)], cwd=PROJECT, text=True, capture_output=True, timeout=180)
        assert run.returncode == 0, f'Release executable failed on alternate signal: {run.stderr}'
        assert_matches(load_result(), expected_alternate)
    finally:
        SIGNAL.write_bytes(original_signal)
        if 'valid_original_result' in locals():
            RESULT.write_bytes(valid_original_result)
        elif original_result is not None:
            RESULT.write_bytes(original_result)
        elif RESULT.exists():
            RESULT.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
