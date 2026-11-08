#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess

import pytest

VENV = '/home/user/venv'
PYTHON = VENV + '/bin/python'
SCRIPT = '/home/user/simulate_selection.py'
PARAMS = '/home/user/params.h5'
RESULTS = '/home/user/results.h5'


def run_python(code, env=None):
    result = subprocess.run(
        [PYTHON, '-c', code],
        cwd='/home/user',
        env={**os.environ, **(env or {})},
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout.strip() or result.stderr.strip()


def test_venv_exists_and_packages_installed():
    assert os.path.isdir(VENV), f'Virtual environment directory {VENV} does not exist.'
    assert os.path.isfile(PYTHON), f'Python executable not found at {PYTHON}.'
    run_python('import numpy, scipy, scipy.integrate, h5py')


def test_results_file_exists():
    assert os.path.isfile(RESULTS), f'Output file {RESULTS} does not exist.'


def test_complete_simulation_behavior():
    checker = r'''
import json
import os
import runpy
import shutil
import subprocess
import sys
from types import SimpleNamespace

import h5py
import numpy as np
import scipy.integrate

SCRIPT = '/home/user/simulate_selection.py'
PARAMS = '/home/user/params.h5'
RESULTS = '/home/user/results.h5'
PYTHON = '/home/user/venv/bin/python'
BACKUP = '/tmp/params.h5.verifier-backup'
EXPECTED_TIME = np.linspace(0.0, 10.0, 1000)


def fail(message):
    raise AssertionError(message)


def read_results():
    if not os.path.isfile(RESULTS):
        fail(f'Output file {RESULTS} does not exist.')
    with h5py.File(RESULTS, 'r') as f:
        if 'time' not in f:
            fail("Dataset 'time' missing from results.h5")
        if 'frequency' not in f:
            fail("Dataset 'frequency' missing from results.h5")
        times = np.asarray(f['time'][:])
        freqs = np.asarray(f['frequency'][:])
    if times.shape != (1000,):
        fail(f'Expected time shape (1000,), got {times.shape}')
    if freqs.shape != (1000,):
        fail(f'Expected frequency shape (1000,), got {freqs.shape}')
    if not np.isfinite(freqs).all():
        fail('Simulation results contain NaN or Inf values.')
    if not np.isfinite(times).all():
        fail('Simulation time points contain NaN or Inf values.')
    if not np.allclose(times, EXPECTED_TIME, rtol=0.0, atol=2e-12):
        fail('The time dataset is not np.linspace(0, 10, 1000).')
    return times, freqs


def expected_solution(y0, r, m):
    a = r - m
    if abs(a) < 1e-12:
        return y0 / (1.0 + r * y0 * EXPECTED_TIME)
    return (a * y0) / (r * y0 + (a - r * y0) * np.exp(-a * EXPECTED_TIME))


def set_params(y0, r, m):
    with h5py.File(PARAMS, 'r+') as f:
        f['y0'][...] = y0
        f['r'][...] = r
        f['m'][...] = m


def execute_instrumented(fake=False):
    harness = r'''
import os
import runpy
from types import SimpleNamespace
import h5py
import numpy as np
import scipy.integrate

fake = os.environ.get('FAKE_SOLVER') == '1'
with h5py.File('/home/user/params.h5', 'r') as f:
    expected_y0 = float(f['y0'][()])
    expected_r = float(f['r'][()])
    expected_m = float(f['m'][()])

original = scipy.integrate.solve_ivp
valid_calls = []

def tracked(fun, t_span, y0, *args, **kwargs):
    method = kwargs.get('method', args[0] if len(args) > 0 else 'RK45')
    t_eval = kwargs.get('t_eval', args[2] if len(args) > 2 else None)
    span_ok = np.allclose(np.asarray(t_span, dtype=float), [0.0, 10.0], rtol=0, atol=1e-12)
    y0_array = np.asarray(y0, dtype=float).reshape(-1)
    y0_ok = y0_array.size == 1 and np.isclose(y0_array[0], expected_y0, rtol=0, atol=1e-12)
    time_ok = t_eval is not None and np.asarray(t_eval).shape == (1000,) and np.allclose(
        np.asarray(t_eval), np.linspace(0, 10, 1000), rtol=0, atol=2e-12)
    method_ok = str(method).upper() in {'BDF', 'RADAU', 'LSODA'}
    try:
        probe = np.array([0.37])
        derivative = np.asarray(fun(0.4321, probe), dtype=float).reshape(-1)[0]
        expected = expected_r * probe[0] * (1.0 - probe[0]) - expected_m * probe[0]
        ode_ok = np.isclose(derivative, expected, rtol=1e-10, atol=1e-10)
    except Exception:
        ode_ok = False
    valid_calls.append(span_ok and y0_ok and time_ok and method_ok and ode_ok)

    if not fake:
        return original(fun, t_span, y0, *args, **kwargs)

    t = np.asarray(t_eval, dtype=float)
    marker = np.linspace(0.211, 0.389, len(t)) + 0.003 * np.sin(np.arange(len(t)) * 0.173)
    def dense(query):
        query = np.asarray(query, dtype=float)
        return np.array([np.interp(query, t, marker)])
    return SimpleNamespace(
        t=t, y=np.array([marker]), sol=dense, success=True, status=0,
        message='verifier synthetic successful solve', nfev=1, njev=1, nlu=1)

scipy.integrate.solve_ivp = tracked
runpy.run_path('/home/user/simulate_selection.py', run_name='__main__')
if not any(valid_calls):
    raise AssertionError('The script did not call scipy.integrate.solve_ivp with the HDF5 parameters, required ODE, t_span, t_eval, and a stiff solver method.')
'''
    env = dict(os.environ)
    env['FAKE_SOLVER'] = '1' if fake else '0'
    proc = subprocess.run([PYTHON, '-c', harness], cwd='/home/user', env=env,
                          capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        fail(proc.stdout.strip() or proc.stderr.strip())


def check_numerical_case(y0, r, m):
    set_params(y0, r, m)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    execute_instrumented(fake=False)
    _, actual = read_results()
    expected = expected_solution(y0, r, m)
    if not np.allclose(actual, expected, rtol=5e-3, atol=2e-5):
        index = int(np.argmax(np.abs(actual - expected)))
        fail(f'Incorrect ODE trajectory at index {index}: expected {expected[index]}, got {actual[index]}')


# Preserve the original verifier's checks on the submitted file.
with h5py.File(PARAMS, 'r') as f:
    original_params = tuple(float(f[name][()]) for name in ('y0', 'r', 'm'))
if not np.allclose(original_params, (0.01, 150.0, 30.0), rtol=0, atol=1e-12):
    fail(f'params.h5 was altered: found {original_params}')

_, initial_freqs = read_results()
if not np.isclose(initial_freqs[-1], 0.8, atol=1e-3):
    fail(f'Numerical integration did not converge to correct steady state. Expected ~0.8, got {initial_freqs[-1]}')

shutil.copy2(PARAMS, BACKUP)
rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))
try:
    # Execute and validate the supplied stiff case and unpredictable additional cases.
    check_numerical_case(0.01, 150.0, 30.0)
    for _ in range(2):
        r = float(rng.uniform(35.0, 110.0))
        m = float(rng.uniform(0.12, 0.55) * r)
        y0 = float(rng.uniform(0.015, 0.22))
        check_numerical_case(y0, r, m)

    # Replace solve_ivp's returned trajectory with a marker. The saved output must
    # follow that marker, proving the solver result is actually used.
    set_params(0.073, 63.0, 17.0)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    execute_instrumented(fake=True)
    _, marked = read_results()
    marker = np.linspace(0.211, 0.389, 1000) + 0.003 * np.sin(np.arange(1000) * 0.173)
    if not np.allclose(marked, marker, rtol=0, atol=1e-12):
        fail('results.h5 is not generated from the trajectory returned by solve_ivp.')
finally:
    shutil.copy2(BACKUP, PARAMS)

# Leave results.h5 as a genuine simulation of the original parameters.
execute_instrumented(fake=False)
_, final_freqs = read_results()
expected = expected_solution(0.01, 150.0, 30.0)
if not np.allclose(final_freqs, expected, rtol=5e-3, atol=2e-5):
    fail('Final regenerated trajectory is inaccurate.')
if not np.isclose(final_freqs[-1], 0.8, atol=1e-3):
    fail(f'Expected final frequency ~0.8, got {final_freqs[-1]}')
'''
    run_python(checker)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
