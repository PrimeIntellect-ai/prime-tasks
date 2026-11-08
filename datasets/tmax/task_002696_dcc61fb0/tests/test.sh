#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys
import tempfile

import numpy as np
import pytest
import scipy.io.wavfile as wav
import scipy.signal as signal

REPO = '/home/user/audio_biquad'
BIQUAD_PATH = os.path.join(REPO, 'biquad.py')
APPLY_PATH = os.path.join(REPO, 'apply_filter.py')
FUZZ_PATH = os.path.join(REPO, 'fuzz_test.py')
FIXTURE_PATH = '/app/test_audio.wav'


def _reference_dfi(samples, coeffs):
    b0, b1, b2, a1, a2 = [float(v) for v in coeffs]
    samples = np.asarray(samples, dtype=np.float64)
    output = np.empty(samples.shape, dtype=np.float64)
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(samples):
        x0 = float(x0)
        y0 = b0*x0 + b1*x1 + b2*x2 - a1*y1 - a2*y2
        output[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return output, (x1, x2, y1, y2)


def _load_filter_class():
    assert os.path.isfile(BIQUAD_PATH), f'Missing implementation: {BIQUAD_PATH}'
    assert not os.path.islink(BIQUAD_PATH), 'biquad.py must be a real source file, not a symlink'

    with open(BIQUAD_PATH, 'r', encoding='utf-8') as fh:
        source = fh.read()
    tree = ast.parse(source, filename=BIQUAD_PATH)

    # The requested repair must remain the custom implementation, not delegate
    # filtering to SciPy.
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(alias.name.split('.')[0] != 'scipy' for alias in node.names), \
                'biquad.py must not replace the custom filter with SciPy'
        elif isinstance(node, ast.ImportFrom):
            assert not (node.module or '').startswith('scipy'), \
                'biquad.py must not replace the custom filter with SciPy'
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in {'lfilter', 'sosfilt'}, \
                    'biquad.py must implement the recurrence itself'
            elif isinstance(node.func, ast.Attribute):
                assert node.func.attr not in {'lfilter', 'sosfilt'}, \
                    'biquad.py must implement the recurrence itself'

    sys.path.insert(0, REPO)
    try:
        if 'biquad' in sys.modules:
            del sys.modules['biquad']
        import biquad
    finally:
        sys.path.pop(0)
    assert hasattr(biquad, 'BiquadFilter'), 'biquad.py must define BiquadFilter'
    return biquad.BiquadFilter


def test_custom_biquad_precision_and_chunk_state():
    BiquadFilter = _load_filter_class()
    rng = np.random.default_rng(20260911)

    cases = []
    n = 12000
    t = np.arange(n, dtype=np.float64)
    resonant_input = (rng.standard_normal(n) * 10000.0
                      + 18000.0 * np.sin(2*np.pi*t/5000.0))
    cases.append(((0.0001, 0.0002, 0.0001, -1.98, 0.9801), resonant_input))
    cases.append(((0.17, -0.08, 0.03, -1.2, 0.36),
                  rng.standard_normal(4096) * 321.25))

    chunk_pattern = (1, 7, 31, 257, 13, 1024, 3, 509)
    for coeffs, samples in cases:
        expected, expected_state = _reference_dfi(samples, coeffs)
        filt = BiquadFilter(*coeffs)
        pieces = []
        pos = 0
        chunk_index = 0
        while pos < len(samples):
            size = chunk_pattern[chunk_index % len(chunk_pattern)]
            part = np.asarray(filt.process(samples[pos:pos+size]))
            assert part.shape == samples[pos:pos+size].shape
            pieces.append(part.astype(np.float64, copy=False))
            pos += size
            chunk_index += 1

        actual = np.concatenate(pieces)
        assert np.all(np.isfinite(actual)), 'Custom filter produced NaN or Inf'
        np.testing.assert_allclose(actual, expected, rtol=3e-6, atol=2e-2)

        state = (filt.x1, filt.x2, filt.y1, filt.y2)
        for name, value in zip(('x1', 'x2', 'y1', 'y2'), state):
            arr = np.asarray(value)
            assert np.issubdtype(arr.dtype, np.floating), f'{name} is not floating point'
            assert arr.dtype.itemsize >= 8, f'{name} is still stored below double precision'
        np.testing.assert_allclose(np.asarray(state, dtype=np.float64),
                                   np.asarray(expected_state),
                                   rtol=5e-11, atol=1e-6)


def test_repository_fuzzer_passes():
    assert os.path.isfile(FUZZ_PATH), f'Missing fuzzer: {FUZZ_PATH}'
    result = subprocess.run(
        [sys.executable, '-m', 'pytest', 'fuzz_test.py', '-x', '--tb=short'],
        cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=120)
    assert result.returncode == 0, 'Repository fuzz test failed:\n' + result.stdout


def test_apply_filter_uses_repaired_implementation():
    assert os.path.isfile(APPLY_PATH), f'Missing CLI: {APPLY_PATH}'
    assert os.path.isfile(FIXTURE_PATH), f'Audio fixture is missing at {FIXTURE_PATH}'
    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, 'cli_filtered.wav')
        result = subprocess.run(
            [sys.executable, APPLY_PATH, FIXTURE_PATH, output_path],
            cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120)
        assert result.returncode == 0, 'apply_filter.py failed:\n' + result.stdout
        assert os.path.isfile(output_path), 'apply_filter.py did not create its output'

        rate, data = wav.read(FIXTURE_PATH)
        data = data.astype(np.float64) / 32768.0 if data.dtype == np.int16 else data
        ref = signal.lfilter([0.0001, 0.0002, 0.0001],
                             [1.0, -1.98, 0.9801], data)
        ref = (np.clip(ref, -1.0, 1.0) * 32767).astype(np.int16)
        out_rate, out = wav.read(output_path)
        assert out_rate == rate
        assert len(out) == len(ref)
        mse = np.mean(((ref.astype(np.float64) - out.astype(np.float64)) / 32768.0) ** 2)
        assert mse < 1e-5, f'CLI output MSE {mse} is not less than threshold 1e-5'


def test_filtered_audio_mse():
    agent_output_path = '/home/user/filtered.wav'
    fixture_path = '/app/test_audio.wav'

    assert os.path.isfile(agent_output_path), f"Agent's output file is missing at {agent_output_path}"
    assert os.path.isfile(fixture_path), f"Audio fixture is missing at {fixture_path}"

    # Generate reference
    rate, data = wav.read(fixture_path)
    if data.dtype == np.int16:
        data = data.astype(np.float64) / 32768.0

    # Filter coefficients as defined in the task
    b = [0.0001, 0.0002, 0.0001]
    a = [1.0, -1.98, 0.9801]

    # Compute reference output
    ref_out = signal.lfilter(b, a, data)
    ref_out = np.clip(ref_out, -1.0, 1.0)
    ref_out_int16 = (ref_out * 32767).astype(np.int16)

    # Read agent output
    agent_rate, agent_data = wav.read(agent_output_path)

    assert agent_rate == rate, f"Agent output sample rate {agent_rate} does not match fixture rate {rate}"
    assert len(agent_data) == len(ref_out_int16), "Agent output length does not match reference length"

    # Calculate MSE on float normalized values
    mse_float = np.mean(((ref_out_int16.astype(np.float64) / 32768.0) - (agent_data.astype(np.float64) / 32768.0))**2)

    assert mse_float < 1e-5, f"MSE {mse_float} is not less than threshold 1e-5"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
