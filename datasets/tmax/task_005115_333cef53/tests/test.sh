#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import sys
import tempfile

import numpy as np
import pytest


def test_root_finder_pkg_installed():
    try:
        import root_finder_pkg
    except ImportError:
        pytest.fail("root_finder_pkg is not installed or cannot be imported. Did you fix setup.py and install it?")


def test_sanitizer_adversarial_corpus():
    sanitizer_script = '/home/user/sanitizer.py'
    assert os.path.isfile(sanitizer_script), f"Sanitizer script missing at {sanitizer_script}"

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.npz')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.npz')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        result = subprocess.run(['python', sanitizer_script, cf], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run(['python', sanitizer_script, ef], capture_output=True)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _is_valid_npz(path):
    with np.load(path, allow_pickle=False) as data:
        if not all(name in data.files for name in ('x', 'a', 'b')):
            return False
        x, a, b = data['x'], data['a'], data['b']
        if x.shape != a.shape or x.shape != b.shape:
            return False
        if not (np.isfinite(x).all() and np.isfinite(a).all() and np.isfinite(b).all()):
            return False
        residual = x ** 3 + a * x + b
        return bool(np.isfinite(residual).all() and np.all(np.abs(residual) <= 1e-4))


def test_sanitizer_unlabeled_generated_inputs():
    sanitizer_script = '/home/user/sanitizer.py'
    assert os.path.isfile(sanitizer_script), f"Sanitizer script missing at {sanitizer_script}"

    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), 'big'))

    with tempfile.TemporaryDirectory(prefix='npz_cases_') as case_dir:
        cases = []

        for mode in ('exact', 'within_tolerance', 'residual_error', 'nan_x',
                     'nan_a', 'inf_b', 'large_scale_error'):
            shape = (int(rng.integers(3, 8)), int(rng.integers(4, 9)), int(rng.integers(2, 5)))
            x = rng.uniform(-4.0, 4.0, shape)
            a = rng.uniform(-8.0, 8.0, shape)
            b = -(x ** 3 + a * x)
            index = tuple(int(rng.integers(0, size)) for size in shape)

            if mode == 'within_tolerance':
                b[index] += float(rng.choice([-1.0, 1.0])) * 7.5e-5
            elif mode == 'residual_error':
                b[index] += float(rng.choice([-1.0, 1.0])) * 3.0e-4
            elif mode == 'nan_x':
                x[index] = np.nan
            elif mode == 'nan_a':
                a[index] = np.nan
            elif mode == 'inf_b':
                b[index] = np.inf
            elif mode == 'large_scale_error':
                x.fill(100.0)
                a.fill(10.0)
                b = -(x ** 3 + a * x)
                b[index] += 1.0e-2

            path = os.path.join(case_dir, secrets.token_hex(16) + '.npz')
            np.savez(path, x=x, a=a, b=b)
            cases.append(path)

        rng.shuffle(cases)
        outcomes = []
        for path in cases:
            expected_clean = _is_valid_npz(path)
            result = subprocess.run(
                [sys.executable, sanitizer_script, path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            outcomes.append(expected_clean)
            expected_code = 0 if expected_clean else 1
            assert result.returncode == expected_code, (
                f"Sanitizer returned {result.returncode} for generated input "
                f"expected to exit {expected_code}. stderr={result.stderr.decode(errors='replace')}"
            )

        assert any(outcomes), "Generated suite unexpectedly had no valid inputs"
        assert not all(outcomes), "Generated suite unexpectedly had no invalid inputs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
