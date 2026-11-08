#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import odeint
from scipy.optimize import curve_fit

SCRIPT_PATH = '/home/user/analysis.py'
CSV_PATH = '/home/user/fitted_params.csv'


def load_analysis_module():
    spec = importlib.util.spec_from_file_location('submitted_analysis', SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, 'Could not load analysis.py as Python code.'
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonical_deriv(y, t, N, beta, gamma):
    S, I, R = y
    infection = beta * S * I / N
    return -infection, infection - gamma * I, gamma * I


def canonical_solve(t, beta, gamma):
    N = 1000
    I0, R0 = 1, 0
    S0 = N - I0 - R0
    result = odeint(canonical_deriv, (S0, I0, R0), t, args=(N, beta, gamma))
    return result[:, 1]


def test_analysis_py_exists():
    """Check if the python script was generated."""
    assert os.path.exists(SCRIPT_PATH), f'Expected script {SCRIPT_PATH} does not exist. Did you convert the notebook?'
    assert os.path.isfile(SCRIPT_PATH), f'Expected {SCRIPT_PATH} to be a file.'


def test_analysis_py_fixed():
    """Keep the original source check and verify the derivative behavior."""
    assert os.path.exists(SCRIPT_PATH), f'Cannot check fix, {SCRIPT_PATH} is missing.'

    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    assert '-beta * S * I' in content or '- beta * S * I' in content or '-1 * beta' in content or '-(beta' in content or '- (beta' in content, \
        'The mathematical bug in the ODE derivative function (dSdt) does not appear to be fixed. It should be negative.'

    module = load_analysis_module()
    assert callable(getattr(module, 'sir_deriv', None)), 'analysis.py must define sir_deriv.'

    for _ in range(8):
        N = 500 + secrets.randbelow(4501)
        S = 1.0 + secrets.randbelow(N - 2)
        I = 1.0 + secrets.randbelow(max(1, N - int(S)))
        R = float(max(0, N - int(S) - int(I)))
        beta = 0.05 + secrets.randbelow(1900) / 1000.0
        gamma = 0.01 + secrets.randbelow(900) / 1000.0
        actual = module.sir_deriv((S, I, R), 0.0, N, beta, gamma)
        expected = canonical_deriv((S, I, R), 0.0, N, beta, gamma)
        assert len(actual) == 3, 'sir_deriv must return three derivatives.'
        assert np.allclose(actual, expected, rtol=1e-11, atol=1e-11), \
            f'sir_deriv returned {actual}; expected {expected}.'
        assert math.isclose(sum(actual), 0.0, rel_tol=1e-11, abs_tol=1e-11), \
            'The SIR derivatives must conserve total population.'


def test_solve_sir_uses_correct_model_and_initial_conditions():
    module = load_analysis_module()
    assert callable(getattr(module, 'solve_sir', None)), 'analysis.py must define solve_sir.'
    t = np.linspace(0.0, 12.0, 17)
    beta = 0.15 + secrets.randbelow(1000) / 1000.0
    gamma = 0.03 + secrets.randbelow(500) / 1000.0
    actual = np.asarray(module.solve_sir(t, beta, gamma), dtype=float)
    expected = canonical_solve(t, beta, gamma)
    assert actual.shape == expected.shape
    assert np.allclose(actual, expected, rtol=1e-7, atol=1e-7), \
        'solve_sir does not integrate the corrected SIR equations with the required initial conditions.'


def test_script_executes_and_generates_output():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f'analysis.py failed when executed:\n{result.stdout}\n{result.stderr}'
    assert os.path.isfile(CSV_PATH), 'Executing analysis.py did not generate fitted_params.csv.'


def test_fitted_params_csv():
    """Check if fitted_params.csv is generated correctly and is the derived fit."""
    assert os.path.exists(CSV_PATH), f'Expected output file {CSV_PATH} does not exist. Did you run the fixed script?'

    with open(CSV_PATH, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f'Expected exactly two comma-separated values in {CSV_PATH}, got: {content}'

    try:
        beta = float(parts[0])
        gamma = float(parts[1])
    except ValueError:
        pytest.fail(f'Could not parse beta and gamma as floats from {CSV_PATH}. Content: {content}')

    assert 0.38 < beta < 0.42, f'Fitted beta value {beta} is out of expected bounds. Is the ODE correct?'
    assert 0.08 < gamma < 0.12, f'Fitted gamma value {gamma} is out of expected bounds. Is the ODE correct?'

    assert len(parts[0].split('.')[-1]) == 4, f'Beta value {parts[0]} is not formatted to 4 decimal places.'
    assert len(parts[1].split('.')[-1]) == 4, f'Gamma value {parts[1]} is not formatted to 4 decimal places.'

    data = pd.read_csv('/home/user/data.csv')
    t = data['day'].to_numpy()
    infected = data['infected'].to_numpy()
    expected_params, _ = curve_fit(
        canonical_solve,
        t,
        infected,
        p0=[0.5, 0.2],
        bounds=(0, [2.0, 1.0]),
    )
    expected_content = f'{expected_params[0]:.4f},{expected_params[1]:.4f}'
    assert content == expected_content, \
        f'fitted_params.csv must contain the optimizer result from the corrected model; expected {expected_content}, got {content}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
