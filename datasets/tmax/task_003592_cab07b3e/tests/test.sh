#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.integrate import quad
from scipy.optimize import minimize_scalar

GENERATOR = Path('/home/user/generator')
SOURCE = Path('/home/user/generator.c')
SAMPLES = Path('/home/user/samples.txt')
FIT = Path('/home/user/fit.py')
RESULT = Path('/home/user/result.txt')


def expected_mle(values):
    values = np.asarray(values, dtype=float)
    mean_x2 = float(np.mean(values * values))

    def objective(a):
        z, error = quad(
            lambda x: np.exp(-(x ** 4) - a * (x ** 2)),
            -np.inf,
            np.inf,
            epsabs=1e-11,
            epsrel=1e-11,
            limit=250,
        )
        assert np.isfinite(z) and z > 0
        assert np.isfinite(error)
        return np.log(z) + a * mean_x2

    optimum = minimize_scalar(
        objective,
        bounds=(-5.0, 5.0),
        method='bounded',
        options={'xatol': 1e-11, 'maxiter': 1000},
    )
    assert optimum.success, optimum.message
    return f'a={optimum.x:.3f}'


def run_fit_and_read_result():
    runner = Path('/tmp/run_fit_checked.py')
    marker = Path('/tmp/fit_quad_calls.txt')
    marker.unlink(missing_ok=True)
    RESULT.unlink(missing_ok=True)
    runner.write_text(
        "import pathlib, runpy, scipy.integrate, sys\n"
        "calls = [0]\n"
        "original = scipy.integrate.quad\n"
        "def tracked(*args, **kwargs):\n"
        "    calls[0] += 1\n"
        "    return original(*args, **kwargs)\n"
        "scipy.integrate.quad = tracked\n"
        "try:\n"
        "    runpy.run_path('/home/user/fit.py', run_name='__main__')\n"
        "finally:\n"
        "    pathlib.Path(sys.argv[1]).write_text(str(calls[0]))\n"
    )
    completed = subprocess.run(
        [sys.executable, str(runner), str(marker)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'fit.py failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert marker.is_file(), 'Could not verify scipy.integrate.quad usage.'
    assert int(marker.read_text().strip()) > 0, 'fit.py did not call scipy.integrate.quad.'
    assert RESULT.is_file(), 'fit.py did not create /home/user/result.txt.'
    content = RESULT.read_text().strip()
    assert re.fullmatch(r'a=-?\d+\.\d{3}', content), (
        f'Result has wrong format: {content!r}'
    )
    return content


def test_generator_executable_exists():
    path = '/home/user/generator'
    assert os.path.isfile(path), f'Executable {path} is missing.'
    assert os.access(path, os.X_OK), f'File {path} is not executable.'


def test_samples_txt_exists():
    path = '/home/user/samples.txt'
    assert os.path.isfile(path), f'File {path} is missing.'

    with open(path, 'r') as f:
        content = f.read().strip().split()

    assert len(content) == 7, f'Expected 7 samples in {path}, found {len(content)}.'


def test_fit_py_exists():
    path = '/home/user/fit.py'
    assert os.path.isfile(path), f'File {path} is missing.'


def test_result_txt_correct():
    path = '/home/user/result.txt'
    assert os.path.isfile(path), f'File {path} is missing.'

    with open(path, 'r') as f:
        content = f.read().strip()

    expected = 'a=-1.649'
    assert content == expected, f"Expected result.txt to contain '{expected}', but found '{content}'."


def test_generator_is_compiled_and_samples_are_its_output():
    assert SOURCE.is_file(), 'generator.c is missing.'
    assert GENERATOR.read_bytes()[:4] == b'\x7fELF', 'generator is not a compiled ELF executable.'

    reference = '/tmp/reference_generator'
    build = subprocess.run(
        ['gcc', str(SOURCE), '-o', reference],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f'generator.c does not compile with gcc:\n{build.stderr}'

    submitted = subprocess.run(
        [str(GENERATOR)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    expected = subprocess.run(
        [reference], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert submitted.returncode == 0, f'generator exited with code {submitted.returncode}.'
    assert expected.returncode == 0, 'The gcc-built reference generator failed.'
    assert submitted.stdout == expected.stdout, 'generator output does not match generator.c.'
    assert SAMPLES.read_bytes() == submitted.stdout, (
        'samples.txt is not the exact redirected standard output of generator.'
    )


def test_fit_executes_and_computes_mle_for_derived_inputs():
    original_samples = SAMPLES.read_bytes()
    original_result = RESULT.read_bytes()
    try:
        original_values = [float(x) for x in original_samples.split()]
        expected_original = expected_mle(original_values)
        assert expected_original == 'a=-1.649', 'Independent MLE disagrees with the required original result.'
        assert run_fit_and_read_result() == expected_original

        rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'big'))
        for target_mean_square in (0.18, 0.48, 0.85):
            values = rng.normal(size=11)
            values *= np.sqrt(target_mean_square / np.mean(values * values))
            SAMPLES.write_text('\n'.join(f'{value:.12f}' for value in values) + '\n')
            expected = expected_mle(values)
            actual = run_fit_and_read_result()
            assert actual == expected, (
                f'For generated samples, expected {expected} but fit.py wrote {actual}.'
            )
    finally:
        SAMPLES.write_bytes(original_samples)
        RESULT.write_bytes(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
