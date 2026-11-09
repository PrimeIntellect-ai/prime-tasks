#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import runpy
import stat
import subprocess
from types import SimpleNamespace

import numpy as np
import pytest

SCRIPT = '/home/user/kinetics/fit_kinetics.py'
OUTPUT = '/home/user/kinetics/optimal_params.txt'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT), f'{SCRIPT} does not exist.'
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular Python file.'

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user/kinetics',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Running {SCRIPT} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT), 'Running fit_kinetics.py did not create optimal_params.txt.'


def load_submission():
    return runpy.run_path(SCRIPT, run_name='fit_kinetics_verifier_import')


def test_integrator_is_stable_and_accurate_on_independent_parameters():
    namespace = load_submission()
    assert callable(namespace.get('euler_integrate')), 'euler_integrate is missing or not callable.'

    k1, k2 = 1.7, 0.6
    times = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
    simulated = np.asarray(namespace['euler_integrate'](k1, k2, times), dtype=float)
    expected = (k1 / (k1 - k2)) * (np.exp(-k2 * times) - np.exp(-k1 * times))

    assert simulated.shape == times.shape
    assert np.all(np.isfinite(simulated)), 'Integrator returned non-finite values.'
    assert np.all(simulated >= -1e-8), 'Integrator returned unphysical negative B concentrations.'
    assert np.allclose(simulated, expected, atol=0.02, rtol=0.02), (
        'euler_integrate is not sufficiently accurate; use a stable small step or robust ODE solver.'
    )


def test_objective_computes_sse_from_simulated_and_reference_B():
    namespace = load_submission()
    assert callable(namespace.get('objective')), 'objective is missing or not callable.'

    custom_times = np.array([0.0, 0.3, 0.9, 1.4])
    custom_reference = np.array([0.05, 0.31, 0.22, 0.11])
    custom_simulation = np.array([0.02, 0.27, 0.29, 0.08])
    calls = []

    def fake_integrator(k1, k2, t_eval):
        calls.append((k1, k2, np.asarray(t_eval).copy()))
        return custom_simulation.copy()

    namespace['t_ref'] = custom_times
    namespace['B_ref'] = custom_reference
    namespace['euler_integrate'] = fake_integrator

    params = np.array([1.37, 0.82])
    actual = namespace['objective'](params)
    expected = float(np.sum((custom_simulation - custom_reference) ** 2))

    assert len(calls) == 1, 'objective must simulate B using euler_integrate.'
    assert math.isclose(calls[0][0], params[0]) and math.isclose(calls[0][1], params[1])
    assert np.array_equal(calls[0][2], custom_times), 'objective must evaluate at t_ref.'
    assert math.isclose(float(actual), expected, rel_tol=1e-12, abs_tol=1e-12), (
        'objective must return the Sum of Squared Errors between simulated B and B_ref.'
    )


def test_main_calls_nelder_mead_with_required_initial_guess(monkeypatch):
    import scipy.optimize

    calls = []

    def fake_minimize(fun, x0, *args, **kwargs):
        calls.append((fun, np.asarray(x0, dtype=float), args, kwargs))
        value = float(fun(np.asarray(x0, dtype=float)))
        assert math.isfinite(value), 'The objective is not finite at the required initial guess.'
        return SimpleNamespace(
            x=np.array([2.0, 0.5]), success=True, fun=value, nit=1, nfev=1, message='verifier stub'
        )

    monkeypatch.setattr(scipy.optimize, 'minimize', fake_minimize)
    previous = open(OUTPUT, 'rb').read() if os.path.isfile(OUTPUT) else None
    try:
        runpy.run_path(SCRIPT, run_name='__main__')
        assert len(calls) == 1, 'The main program must call scipy.optimize.minimize exactly once.'
        _, x0, positional, kwargs = calls[0]
        assert np.allclose(x0, [1.0, 1.0]), 'minimize must use the initial guess [1.0, 1.0].'
        method = kwargs.get('method')
        assert method == 'Nelder-Mead', 'minimize must use method="Nelder-Mead".'
        assert os.path.isfile(OUTPUT), 'The main program did not save the optimizer result.'
        with open(OUTPUT, 'r') as f:
            assert f.read().strip() == '2.00,0.50', 'The optimized result must be written with two decimals.'
    finally:
        if previous is None:
            if os.path.lexists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, 'wb') as f:
                f.write(previous)


def test_optimal_params_file_exists():
    file_path = '/home/user/kinetics/optimal_params.txt'
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The script must save the optimal parameters to this file."


def test_optimal_params_content_format():
    file_path = '/home/user/kinetics/optimal_params.txt'
    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {file_path} is empty."

    parts = content.split(',')
    assert len(parts) == 2, f"File {file_path} must contain exactly two values separated by a comma. Found: '{content}'"

    for part in parts:
        part = part.strip()
        assert '.' in part, f"Value '{part}' does not have a decimal point."
        decimals = part.split('.')[1]
        assert len(decimals) == 2, f"Value '{part}' is not rounded to exactly two decimal places."


def test_optimal_params_values():
    file_path = '/home/user/kinetics/optimal_params.txt'
    with open(file_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    try:
        k1 = float(parts[0].strip())
        k2 = float(parts[1].strip())
    except ValueError:
        pytest.fail(f"Could not parse parameters as floats: '{content}'")

    expected_k1 = 2.00
    expected_k2 = 0.50

    assert math.isclose(k1, expected_k1, abs_tol=0.1), f"k1 value {k1} is not close enough to expected {expected_k1}."
    assert math.isclose(k2, expected_k2, abs_tol=0.1), f"k2 value {k2} is not close enough to expected {expected_k2}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
