#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import time
import ctypes
import importlib
import subprocess
import pytest
import numpy as np
from scipy.io import wavfile

WORKSPACE = '/home/user/pr_workspace'
LIB_PATH = os.path.join(WORKSPACE, 'librms.so')
OUTPUT_PATH = '/home/user/output.npy'
AUDIO_PATH = '/app/sample.wav'


def reference_rms(x, window_size):
    x = np.ascontiguousarray(x, dtype=np.float32)
    result = np.empty(x.shape, dtype=np.float32)
    half = window_size // 2
    squared = x ** 2
    for i in range(len(x)):
        start = max(0, i - half)
        end = min(len(x) - 1, i + half)
        result[i] = np.sqrt(np.mean(squared[start:end + 1]))
    return result


def assert_correct(actual, expected, context):
    actual = np.asarray(actual)
    assert actual.shape == expected.shape, f'{context}: shape mismatch'
    assert actual.dtype == np.float32, f'{context}: expected float32 output, got {actual.dtype}'
    assert np.all(np.isfinite(actual)), f'{context}: output contains NaN or infinity'
    mse = np.mean((actual.astype(np.float64) - expected.astype(np.float64)) ** 2)
    assert mse < 1e-5, f'{context}: MSE {mse:.6e}, expected < 1e-5'


def test_final_state():
    makefile_path = os.path.join(WORKSPACE, 'Makefile')
    assert os.path.isfile(makefile_path), 'Makefile is missing.'
    makefile_text = open(makefile_path, encoding='utf-8', errors='replace').read().lower()
    assert '-fpic' in makefile_text, 'Makefile does not enable position-independent code with -fPIC.'
    assert '-shared' in makefile_text, 'Makefile does not build a shared library with -shared.'

    # Require the submitted Makefile to recreate the library rather than trusting
    # a previously built artifact.
    if os.path.lexists(LIB_PATH):
        os.unlink(LIB_PATH)
    build = subprocess.run(
        ['make', '-B'], cwd=WORKSPACE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert build.returncode == 0, f'make failed:\n{build.stdout}'
    assert os.path.isfile(LIB_PATH), 'make did not produce librms.so.'

    assert os.path.isfile(OUTPUT_PATH), f'{OUTPUT_PATH} is missing.'
    assert os.path.isfile(AUDIO_PATH), f'{AUDIO_PATH} is missing.'

    try:
        lib = ctypes.CDLL(LIB_PATH)
    except Exception as exc:
        pytest.fail(f'Failed to load {LIB_PATH}: {exc}')

    try:
        c_function = lib.compute_rms
    except AttributeError:
        pytest.fail("Function 'compute_rms' not found in librms.so")

    c_function.argtypes = [
        np.ctypeslib.ndpointer(dtype=np.float32, ndim=1, flags='C_CONTIGUOUS'),
        ctypes.c_int,
        ctypes.c_int,
        np.ctypeslib.ndpointer(dtype=np.float32, ndim=1, flags='C_CONTIGUOUS'),
    ]
    c_function.restype = None

    # Exercise the C implementation on independently generated, nontrivial data
    # and several window sizes. The expected values are computed by the verifier.
    rng = np.random.default_rng(731942)
    x = np.concatenate([
        np.zeros(311, dtype=np.float32),
        np.linspace(-1.0, 1.0, 777, dtype=np.float32),
        (0.65 * np.sin(np.arange(1201, dtype=np.float32) * 0.071)).astype(np.float32),
        rng.uniform(-1.0, 1.0, 1808).astype(np.float32),
    ])
    for window_size in (1, 16, 127, 1024):
        expected = reference_rms(x, window_size)
        actual = np.zeros_like(x)
        c_function(x, len(x), window_size, actual)
        assert_correct(actual, expected, f'direct C call, window={window_size}')

    # Import and exercise wrapper.py itself, and verify that its declared ABI uses
    # float pointers and C int arguments rather than the original double pointers.
    sys.path.insert(0, WORKSPACE)
    sys.modules.pop('wrapper', None)
    try:
        wrapper = importlib.import_module('wrapper')
    except Exception as exc:
        pytest.fail(f'Failed to import wrapper.py: {exc}')

    assert hasattr(wrapper, 'compute_rms_c'), 'wrapper.py does not define compute_rms_c.'
    assert hasattr(wrapper, 'lib') and hasattr(wrapper.lib, 'compute_rms'), 'wrapper.py does not expose the loaded compute_rms function.'
    argtypes = wrapper.lib.compute_rms.argtypes
    assert argtypes is not None and len(argtypes) == 4, 'wrapper.py does not set all four compute_rms argtypes.'

    def is_float32_pointer(value):
        if getattr(value, '_type_', None) is ctypes.c_float:
            return True
        dtype = getattr(value, '_dtype_', None)
        try:
            return dtype is not None and np.dtype(dtype) == np.dtype(np.float32)
        except Exception:
            return False

    assert is_float32_pointer(argtypes[0]), 'wrapper.py input argtype is not a float32 pointer.'
    assert argtypes[1] is ctypes.c_int and argtypes[2] is ctypes.c_int, 'wrapper.py length and window argtypes must be ctypes.c_int.'
    assert is_float32_pointer(argtypes[3]), 'wrapper.py output argtype is not a float32 pointer.'
    assert wrapper.lib.compute_rms.restype is None, 'wrapper.py must set the void return type to None.'

    for window_size in (16, 127, 1024):
        expected = reference_rms(x, window_size)
        wrapped = wrapper.compute_rms_c(x, window_size)
        assert_correct(wrapped, expected, f'wrapper call, window={window_size}')

    # Execute the requested benchmark as an integration check of benchmark.py,
    # wrapper.py, and the rebuilt shared library.
    benchmark = subprocess.run(
        ['python3', 'benchmark.py', AUDIO_PATH], cwd=WORKSPACE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert benchmark.returncode == 0, f'benchmark.py failed:\n{benchmark.stdout}'
    assert 'Success!' in benchmark.stdout, f'benchmark.py did not report success:\n{benchmark.stdout}'

    _, data = wavfile.read(AUDIO_PATH)
    data = np.ascontiguousarray(data.astype(np.float32))
    num_samples = len(data)
    window_size = 1024
    output = np.zeros_like(data, dtype=np.float32)

    start_time = time.perf_counter()
    c_function(data, num_samples, window_size, output)
    execution_time = time.perf_counter() - start_time
    assert execution_time <= 0.05, (
        f'Execution time {execution_time:.4f}s exceeds threshold of 0.05s. '
        'The C implementation is likely still O(N*W).'
    )
    assert np.all(np.isfinite(output)), 'The computed RMS output contains NaN or infinity.'
    assert np.max(output) > 0.0, 'The computed RMS output is entirely zeros, indicating a flawed algorithm.'

    # Check values from across the full audio against the reference definition.
    # Normalize as benchmark.py does so the required MSE has the same scale.
    normalized = data / np.float32(32768.0)
    indices = np.unique(np.concatenate([
        np.arange(0, 16),
        np.arange(num_samples - 16, num_samples),
        np.linspace(0, num_samples - 1, 512, dtype=np.int64),
    ]))
    half = window_size // 2
    expected_points = np.empty(len(indices), dtype=np.float32)
    for j, i in enumerate(indices):
        lo = max(0, int(i) - half)
        hi = min(num_samples - 1, int(i) + half)
        expected_points[j] = np.sqrt(np.mean(normalized[lo:hi + 1] ** 2))
    actual_points = output[indices] / np.float32(32768.0)
    point_mse = np.mean((actual_points.astype(np.float64) - expected_points.astype(np.float64)) ** 2)
    assert point_mse < 1e-5, f'C output disagrees with reference moving RMS; sampled MSE is {point_mse:.6e}'

    try:
        student_output = np.load(OUTPUT_PATH, allow_pickle=False)
    except Exception as exc:
        pytest.fail(f'Failed to load {OUTPUT_PATH}: {exc}')

    assert student_output.shape == output.shape, (
        f'Shape mismatch: saved output has shape {student_output.shape}, expected {output.shape}'
    )
    assert np.all(np.isfinite(student_output)), 'Saved output contains NaN or infinity.'
    mse = np.mean((student_output.astype(np.float64) - output.astype(np.float64)) ** 2)
    assert mse < 1e-5, f'MSE between C output and saved output.npy is {mse:.6e}, expected < 1e-5'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
