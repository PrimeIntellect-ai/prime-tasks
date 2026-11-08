#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import random
import subprocess
import tempfile

import pytest

PIPELINE = '/home/user/pipeline'
CALC_C = os.path.join(PIPELINE, 'calc.c')
LIBCALC = os.path.join(PIPELINE, 'libcalc.so')
PROCESS_PY = os.path.join(PIPELINE, 'process.py')
RESULTS = os.path.join(PIPELINE, 'results.json')


def load_library(path):
    lib = ctypes.CDLL(path)
    lib.process_data.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    lib.process_data.restype = ctypes.c_double
    return lib


def exercise_library(path):
    assert os.path.isfile(path), f'{path} is missing.'
    lib = load_library(path)

    # This case simultaneously exposes an inclusive upper bound and a float
    # accumulator. The final array element is a sentinel outside the requested
    # logical length.
    values = [1.0] + [2.0 ** -30] * 10000
    expected = sum(values)
    values.append(987654321.0)
    array = (ctypes.c_double * len(values))(*values)
    actual = lib.process_data(array, len(values) - 1)
    assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-12), \
        f'process_data returned {actual}, expected {expected}'

    # Exercise additional independently derived inputs and nonzero sentinels.
    rng = random.Random(731942)
    for length in (1, 2, 7, 31, 257):
        logical = [rng.uniform(-1000.0, 1000.0) for _ in range(length)]
        expected = sum(logical)
        storage = logical + [rng.choice((-1.0, 1.0)) * 1.0e15]
        array = (ctypes.c_double * len(storage))(*storage)
        actual = lib.process_data(array, length)
        assert math.isclose(actual, expected, rel_tol=1e-13, abs_tol=1e-10), \
            f'process_data failed for length {length}: got {actual}, expected {expected}'


def test_bad_txn_txt():
    path = os.path.join(PIPELINE, 'bad_txn.txt')
    assert os.path.isfile(path), f'{path} is missing. The transaction ID was not extracted.'
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == 'TXN-A839F7X2', \
        f"bad_txn.txt contains '{content}', expected exactly 'TXN-A839F7X2'."


def test_calc_c_fixes():
    assert os.path.isfile(CALC_C), f'{CALC_C} is missing.'
    with open(CALC_C, 'r') as f:
        content = f.read()

    # Retain the original source assertions.
    assert 'float sum' not in content, \
        "calc.c still contains 'float sum'. The precision loss bug was not fixed."
    assert 'double sum' in content, \
        "calc.c does not contain 'double sum'. The accumulator should be upgraded to double."
    assert 'i <= len' not in content, \
        "calc.c still contains the off-by-one error 'i <= len'."
    assert 'i < len' in content, \
        "calc.c does not contain the fixed loop bounds 'i < len'."

    # Compile the submitted source into a verifier-owned artifact and exercise it,
    # so comments or dead code cannot satisfy the source checks.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, 'libcalc_verifier.so')
        completed = subprocess.run(
            ['gcc', '-shared', '-o', rebuilt, '-fPIC', CALC_C],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert completed.returncode == 0, f'calc.c did not compile: {completed.stderr}'
        exercise_library(rebuilt)


def test_installed_library_and_run_pipeline():
    # The installed shared object must itself be a working build, not merely a
    # stale buggy library alongside corrected source.
    exercise_library(LIBCALC)
    assert os.path.isfile(PROCESS_PY), f'{PROCESS_PY} is missing.'

    # Do not trust an agent-created results file: remove it and execute the
    # supplied processing script against the installed library.
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    completed = subprocess.run(
        ['python3', PROCESS_PY],
        cwd=PIPELINE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert completed.returncode == 0, \
        f'process.py failed with exit code {completed.returncode}: {completed.stderr}'
    assert os.path.isfile(RESULTS), \
        f'{RESULTS} is missing. The script was not run successfully after compilation.'


def test_results_json():
    assert os.path.isfile(RESULTS), \
        f'{RESULTS} is missing. The script was not run successfully after compilation.'
    with open(RESULTS, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{RESULTS} does not contain valid JSON.')

    assert 'status' in data and data['status'] == 'success', \
        "results.json status is missing or not 'success'."
    assert 'final_sum' in data, "results.json is missing 'final_sum'."

    # Retain the original expected-value assertion.
    expected_sum = 1000000000000.006
    actual_sum = data['final_sum']
    assert math.isclose(actual_sum, expected_sum, rel_tol=1e-9), \
        f'final_sum {actual_sum} is not close to expected {expected_sum}.'

    # Also derive the exact result of the specified input and summation order.
    inputs = [100000000.0, 0.0000001, 0.0000002, 0.0000003] * 10000
    sequential_double_sum = sum(inputs)
    assert math.isclose(actual_sum, sequential_double_sum, rel_tol=0.0, abs_tol=1e-9), \
        f'final_sum {actual_sum} does not match executed double-precision calculation {sequential_double_sum}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
