#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pytest

SOURCE = Path('/home/user/fitter.cpp')
DATA = Path('/app/measurements.csv')
OUTPUT = Path('/home/user/model_weights.txt')
BINARY = Path('/tmp/fitter_submission')


def compile_submission():
    assert SOURCE.is_file(), f'Source file not found at {SOURCE}'
    assert not SOURCE.is_symlink(), f'{SOURCE} must be a regular source file'
    result = subprocess.run(
        ['g++', '-O2', '-std=c++17', '-fopenmp', str(SOURCE), '-o', str(BINARY)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f'Failed to compile fitter.cpp:\n{result.stdout}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Compilation did not produce an executable'


def parse_weights():
    assert OUTPUT.is_file(), f'Output file not found at {OUTPUT}'
    content = OUTPUT.read_text().strip()
    assert content, f'Output file {OUTPUT} is empty'
    try:
        weights = np.array([float(x.strip()) for x in content.split(',')], dtype=float)
    except ValueError as exc:
        pytest.fail(f'Failed to parse comma-separated floats from {OUTPUT}: {exc}')
    assert len(weights) == 3, f'Expected 3 weights, got {len(weights)}: {weights}'
    assert np.all(np.isfinite(weights)), f'Weights must all be finite: {weights}'
    return weights, OUTPUT.read_bytes()


def run_submission():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '4'
    result = subprocess.run(
        [str(BINARY)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f'Compiled fitter failed:\n{result.stdout}'
    return parse_weights()


def write_perturbed_dataset(original, shifts):
    d0, d1, d2 = shifts
    with DATA.open('w') as out:
        for lineno, raw in enumerate(original.splitlines(), 1):
            if not raw.strip():
                continue
            fields = raw.split(',')
            assert len(fields) == 2, f'Invalid original CSV row {lineno}'
            x = float(fields[0])
            y = float(fields[1])
            # Add a verifier-chosen combination of the three model basis terms.
            changed = y + d0 + d1 * math.sin(x - 420.0) + d2 * math.exp(-0.01 * x)
            out.write(f'{fields[0]},{changed:.17g}\n')


def test_compiled_fitter_accuracy_determinism_and_data_dependence():
    assert DATA.is_file(), f'Dataset not found at {DATA}'
    original_data = DATA.read_text()
    old_output = OUTPUT.read_bytes() if OUTPUT.is_file() else None
    baseline_bytes = None

    try:
        compile_submission()

        # Execute the submitted source, rather than trusting a pre-created output file.
        baseline, baseline_bytes = run_submission()
        baseline_again, baseline_again_bytes = run_submission()
        assert baseline_bytes == baseline_again_bytes, (
            f'Repeated runs were not exactly deterministic: {baseline} vs {baseline_again}'
        )

        # Preserve the original verifier's golden-reference accuracy assertion.
        true_weights = np.array([2.45012, -1.30400, 0.04599])
        l2_error = np.linalg.norm(baseline - true_weights)
        threshold = 1e-4
        assert l2_error <= threshold, (
            f'L2 Error exceeds threshold. Measured L2 Error: {l2_error:.6e}, '
            f'Threshold: {threshold:.6e}. Agent weights: {baseline}, '
            f'True weights: {true_weights}'
        )

        # A genuine fitter is equivariant when model-basis terms are added to y.
        # Random shifts are selected only after the agent has finished.
        rng = secrets.SystemRandom()
        shifts = np.array([
            rng.choice((-1.0, 1.0)) * rng.uniform(0.20, 0.45),
            rng.choice((-1.0, 1.0)) * rng.uniform(0.12, 0.28),
            rng.choice((-1.0, 1.0)) * rng.uniform(0.015, 0.040),
        ])
        write_perturbed_dataset(original_data, shifts)

        changed, changed_bytes = run_submission()
        changed_again, changed_again_bytes = run_submission()
        assert changed_bytes == changed_again_bytes, (
            f'Repeated perturbed-data runs were not exactly deterministic: '
            f'{changed} vs {changed_again}'
        )

        expected_changed = baseline + shifts
        changed_error = np.linalg.norm(changed - expected_changed)
        assert changed_error <= 2e-4, (
            'The executable did not fit verifier-perturbed measurements. '
            f'Expected approximately {expected_changed}, got {changed}; '
            f'L2 error {changed_error:.6e}'
        )
    finally:
        DATA.write_text(original_data)
        if baseline_bytes is not None:
            OUTPUT.write_bytes(baseline_bytes)
        elif old_output is not None:
            OUTPUT.write_bytes(old_output)
        elif OUTPUT.exists() or OUTPUT.is_symlink():
            OUTPUT.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
