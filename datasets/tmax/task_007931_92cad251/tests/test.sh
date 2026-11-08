#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_profiled.py
import runpy
import sys
import scipy.integrate

count = 0
real_solve_ivp = scipy.integrate.solve_ivp

def counted_solve_ivp(*args, **kwargs):
    global count
    count += 1
    return real_solve_ivp(*args, **kwargs)

scipy.integrate.solve_ivp = counted_solve_ivp
try:
    runpy.run_path(sys.argv[1], run_name='__main__')
finally:
    with open('/tmp/solve_ivp_count.txt', 'w') as f:
        f.write(str(count))
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest
from scipy.integrate import solve_ivp

SCRIPT_FILE = '/home/user/mcmc_profiler.py'
RESULTS_FILE = '/home/user/results.json'
DATA_FILE = '/home/user/data.csv'
COUNT_FILE = '/tmp/solve_ivp_count.txt'
RUNNER = '/tmp/run_profiled.py'


def run_submission():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    if os.path.exists(COUNT_FILE):
        os.remove(COUNT_FILE)

    completed = subprocess.run(
        [sys.executable, RUNNER, SCRIPT_FILE],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f'{SCRIPT_FILE} failed when executed.\n'
        f'stdout:\n{completed.stdout}\n'
        f'stderr:\n{completed.stderr}'
    )
    assert os.path.isfile(COUNT_FILE), 'Could not verify solve_ivp usage.'
    with open(COUNT_FILE) as f:
        solve_count = int(f.read())
    assert solve_count >= 1000, (
        'The executed sampler did not use scipy.integrate.solve_ivp for its '
        f'MCMC likelihood evaluations (observed only {solve_count} calls).'
    )


def load_results():
    with open(RESULTS_FILE, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{RESULTS_FILE} does not contain valid JSON.')


def reference_mcmc(t, y_obs):
    def log_posterior(theta):
        if not (0.0 < theta < 1.0):
            return -np.inf
        solution = solve_ivp(
            lambda time, y: -theta * y,
            (float(t[0]), float(t[-1])),
            [100.0],
            t_eval=t,
        )
        assert solution.success
        y_pred = solution.y[0]
        return float(np.sum(-0.5 * ((y_obs - y_pred) / 2.0) ** 2))

    np.random.seed(42)
    theta_current = 0.1
    current_logp = log_posterior(theta_current)
    samples = []
    accepted = 0

    for _ in range(5000):
        theta_prop = np.random.normal(theta_current, 0.05)
        u = np.random.rand()
        proposal_logp = log_posterior(theta_prop)
        if np.log(u) < proposal_logp - current_logp:
            theta_current = theta_prop
            current_logp = proposal_logp
            accepted += 1
        samples.append(theta_current)

    return float(np.mean(samples[1000:])), accepted / 5000.0


def test_script_exists_and_is_python_using_solve_ivp():
    assert os.path.isfile(SCRIPT_FILE), f'{SCRIPT_FILE} is missing.'
    assert not os.path.islink(SCRIPT_FILE), f'{SCRIPT_FILE} must be a Python script, not a symlink.'
    with open(SCRIPT_FILE, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT_FILE} is not valid Python: {exc}')

    calls_solve_ivp = any(
        isinstance(node, ast.Call)
        and (
            isinstance(node.func, ast.Name) and node.func.id == 'solve_ivp'
            or isinstance(node.func, ast.Attribute) and node.func.attr == 'solve_ivp'
        )
        for node in ast.walk(tree)
    )
    assert calls_solve_ivp, f'{SCRIPT_FILE} does not call scipy.integrate.solve_ivp.'


def test_execute_script_on_provided_data():
    run_submission()


def test_results_file_exists():
    """Check if the results.json file was created."""
    assert os.path.isfile(RESULTS_FILE), f"{RESULTS_FILE} is missing. Did the script run and save the output?"


def test_results_file_content():
    """Validate the structure and values in results.json."""
    with open(RESULTS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_FILE} does not contain valid JSON.")

    assert isinstance(data, dict), f"Expected a JSON object (dictionary) in {RESULTS_FILE}."

    assert "theta_mean" in data, "The key 'theta_mean' is missing from the JSON output."
    assert "acceptance_rate" in data, "The key 'acceptance_rate' is missing from the JSON output."

    theta_mean = data["theta_mean"]
    acc_rate = data["acceptance_rate"]

    assert isinstance(theta_mean, (int, float)), "'theta_mean' must be a numeric value."
    assert isinstance(acc_rate, (int, float)), "'acceptance_rate' must be a numeric value."

    expected_theta_mean = 0.3015
    expected_acc_rate = 0.3546

    assert math.isclose(theta_mean, expected_theta_mean, abs_tol=1e-3), \
        f"Expected theta_mean to be approximately {expected_theta_mean}, but got {theta_mean}. Check your MCMC logic, burn-in, and random seeding."

    assert math.isclose(acc_rate, expected_acc_rate, abs_tol=1e-3), \
        f"Expected acceptance_rate to be approximately {expected_acc_rate}, but got {acc_rate}. Ensure the acceptance criterion and proposal distributions are correct."


def test_sampler_on_independently_derived_dataset():
    original_data = open(DATA_FILE, 'rb').read()
    original_results = open(RESULTS_FILE, 'rb').read()

    t = np.arange(11, dtype=float)
    noise = np.array([1.1, -0.8, 0.4, -1.3, 0.7, 1.5, -0.5, 0.2, -1.0, 0.9, -0.3])
    y_obs = 100.0 * np.exp(-0.62 * t) + noise
    expected_mean, expected_rate = reference_mcmc(t, y_obs)

    try:
        with open(DATA_FILE, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['t', 'y_obs'])
            writer.writerows(zip(t, y_obs))

        run_submission()
        assert os.path.isfile(RESULTS_FILE), f'{RESULTS_FILE} was not created on the test dataset.'
        data = load_results()
        assert isinstance(data, dict)
        assert set(data) == {'theta_mean', 'acceptance_rate'}
        assert isinstance(data['theta_mean'], (int, float)) and not isinstance(data['theta_mean'], bool)
        assert isinstance(data['acceptance_rate'], (int, float)) and not isinstance(data['acceptance_rate'], bool)
        assert math.isclose(data['theta_mean'], expected_mean, abs_tol=1e-3), (
            f"On a changed dataset, expected theta_mean approximately {expected_mean}, "
            f"but got {data['theta_mean']}."
        )
        assert math.isclose(data['acceptance_rate'], expected_rate, abs_tol=1e-3), (
            f"On a changed dataset, expected acceptance_rate approximately {expected_rate}, "
            f"but got {data['acceptance_rate']}."
        )
    finally:
        with open(DATA_FILE, 'wb') as f:
            f.write(original_data)
        with open(RESULTS_FILE, 'wb') as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
