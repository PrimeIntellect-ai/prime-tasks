#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -f /home/user/profiling_results.json /tmp/profile_runtime.json

cat << 'HARNESS_EOF' > /tmp/run_profile_instrumented.py
import json
import os
import runpy
import numpy as np
import pandas as pd
import scipy.optimize
import scipy.stats

SCRIPT = '/home/user/profile_latencies.py'
RECORDS = '/tmp/profile_runtime.json'
DATA_FILE = '/home/user/latencies.csv'

if not os.path.isfile(SCRIPT):
    raise FileNotFoundError(SCRIPT)

data = pd.read_csv(DATA_FILE)['latency_ms'].to_numpy(dtype=float)
real_minimize = scipy.optimize.minimize
real_wasserstein = scipy.stats.wasserstein_distance
records = {'minimize': [], 'wasserstein': []}

def tracked_minimize(fun, x0, *args, **kwargs):
    method = kwargs.get('method')
    if method is None and len(args) >= 2:
        method = args[1]
    values = []

    def tracked_objective(x, *fun_args):
        value = fun(x, *fun_args)
        try:
            values.append(float(value))
        except Exception:
            pass
        return value

    result = real_minimize(tracked_objective, x0, *args, **kwargs)
    finite_values = [v for v in values if np.isfinite(v)]
    records['minimize'].append({
        'method': None if method is None else str(method),
        'evaluations': len(values),
        'unique_finite_values': len(set(round(v, 10) for v in finite_values)),
        'success': bool(getattr(result, 'success', False)),
    })
    return result

def tracked_wasserstein(u_values, v_values, *args, **kwargs):
    u = np.asarray(u_values, dtype=float).reshape(-1)
    v = np.asarray(v_values, dtype=float).reshape(-1)
    value = real_wasserstein(u_values, v_values, *args, **kwargs)

    def is_empirical(a):
        return len(a) == len(data) and np.array_equal(np.sort(a), np.sort(data))

    records['wasserstein'].append({
        'u_len': int(len(u)),
        'v_len': int(len(v)),
        'u_is_empirical': bool(is_empirical(u)),
        'v_is_empirical': bool(is_empirical(v)),
        'value': float(value),
    })
    return value

scipy.optimize.minimize = tracked_minimize
scipy.stats.wasserstein_distance = tracked_wasserstein
os.chdir('/home/user')
try:
    runpy.run_path(SCRIPT, run_name='__main__')
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise
finally:
    with open(RECORDS, 'w') as f:
        json.dump(records, f)
HARNESS_EOF

if ! timeout 180s python3 /tmp/run_profile_instrumented.py; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import minimize

RESULTS_FILE = '/home/user/profiling_results.json'
SCRIPT_FILE = '/home/user/profile_latencies.py'
DATA_FILE = '/home/user/latencies.csv'
RUNTIME_FILE = '/tmp/profile_runtime.json'
EXPECTED_KEYS = {'mu1', 'sigma1', 'mu2', 'sigma2', 'w1', 'wasserstein_distance'}


def load_results():
    with open(RESULTS_FILE, 'r') as f:
        return json.load(f)


def expected_input_data():
    np.random.seed(42)
    n_samples = 5000
    n1 = int(n_samples * 0.85)
    data1 = np.random.normal(45.0, 8.0, n1)
    data2 = np.random.normal(210.0, 40.0, n_samples - n1)
    data = np.concatenate([data1, data2])
    np.random.shuffle(data)
    return data


@pytest.fixture(scope='session')
def reference_fit():
    x = pd.read_csv(DATA_FILE)['latency_ms'].to_numpy(dtype=float)
    ordered = np.sort(x)
    split = int(0.85 * len(ordered))
    low, high = ordered[:split], ordered[split:]

    def logit(p):
        return math.log(p / (1.0 - p))

    initial = np.array([
        logit(0.85),
        float(low.mean()),
        math.log(max(float(low.std()), 0.2) - 0.1),
        float(high.mean()),
        math.log(max(float(high.std()), 0.2) - 0.1),
    ])

    def unpack(t):
        w = 1.0 / (1.0 + np.exp(-t[0]))
        return w, t[1], 0.1 + np.exp(t[2]), t[3], 0.1 + np.exp(t[4])

    def nll(t):
        w, mu1, sigma1, mu2, sigma2 = unpack(t)
        logp1 = math.log(w) - math.log(sigma1) - 0.5 * ((x - mu1) / sigma1) ** 2
        logp2 = math.log1p(-w) - math.log(sigma2) - 0.5 * ((x - mu2) / sigma2) ** 2
        return float(-np.sum(np.logaddexp(logp1, logp2)))

    fit = minimize(
        nll,
        initial,
        method='Nelder-Mead',
        options={'maxiter': 20000, 'xatol': 1e-9, 'fatol': 1e-7},
    )
    w, mu1, sigma1, mu2, sigma2 = unpack(fit.x)
    if mu1 > mu2:
        w, mu1, sigma1, mu2, sigma2 = 1.0 - w, mu2, sigma2, mu1, sigma1
    return {'w1': w, 'mu1': mu1, 'sigma1': sigma1, 'mu2': mu2, 'sigma2': sigma2}


def test_analysis_script_exists_and_is_python_file():
    assert os.path.isfile(SCRIPT_FILE), f'The file {SCRIPT_FILE} does not exist.'
    assert not os.path.islink(SCRIPT_FILE), 'The analysis script must be a real Python file.'
    with open(SCRIPT_FILE, 'r') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_FILE)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(not alias.name.startswith('sklearn') for alias in node.names), \
                'Off-the-shelf sklearn GMM fitting is not allowed.'
        if isinstance(node, ast.ImportFrom):
            assert not (node.module or '').startswith('sklearn'), \
                'Off-the-shelf sklearn GMM fitting is not allowed.'


def test_input_latency_data_was_not_replaced():
    actual = pd.read_csv(DATA_FILE)['latency_ms'].to_numpy(dtype=float)
    expected = expected_input_data()
    assert actual.shape == expected.shape
    assert np.allclose(actual, expected, rtol=0, atol=1e-12), 'latencies.csv was modified.'


def test_results_file_exists():
    """Test that the profiling_results.json file exists."""
    assert os.path.isfile(RESULTS_FILE), f'The file {RESULTS_FILE} does not exist.'


def test_results_json_keys():
    """Test that the results JSON contains the exact required keys."""
    try:
        res = load_results()
    except json.JSONDecodeError:
        pytest.fail(f'The file {RESULTS_FILE} is not valid JSON.')
    assert set(res.keys()) == EXPECTED_KEYS, \
        f'JSON keys {set(res.keys())} do not match expected {EXPECTED_KEYS}.'
    for key, value in res.items():
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f'{key} is not numeric.'
        assert math.isfinite(value), f'{key} is not finite.'


def test_results_bounds():
    """Test that the optimized parameters and distance metric fall within acceptable bounds."""
    res = load_results()
    assert 0.80 <= res['w1'] <= 0.90, f"w1 out of bounds: {res['w1']}"
    assert 40.0 <= res['mu1'] <= 50.0, f"mu1 out of bounds: {res['mu1']}"
    assert 6.0 <= res['sigma1'] <= 10.0, f"sigma1 out of bounds: {res['sigma1']}"
    assert 190.0 <= res['mu2'] <= 230.0, f"mu2 out of bounds: {res['mu2']}"
    assert 30.0 <= res['sigma2'] <= 50.0, f"sigma2 out of bounds: {res['sigma2']}"
    assert 0.0 <= res['wasserstein_distance'] <= 15.0, \
        f"wasserstein_distance out of bounds: {res['wasserstein_distance']}"


def test_component_ordering():
    """Test that component 1 represents the fast responses (lower mean)."""
    res = load_results()
    assert res['mu1'] < res['mu2'], 'Components are swapped: mu1 should be less than mu2.'


def test_nelder_mead_custom_objective_was_executed():
    with open(RUNTIME_FILE, 'r') as f:
        runtime = json.load(f)
    valid = [r for r in runtime['minimize']
             if (r['method'] or '').lower().replace('_', '-') == 'nelder-mead'
             and r['evaluations'] >= 10
             and r['unique_finite_values'] >= 5]
    assert valid, 'The script did not execute scipy.optimize.minimize with Nelder-Mead and a varying objective.'


def test_fitted_parameters_match_data_mle(reference_fit):
    res = load_results()
    tolerances = {'w1': 0.015, 'mu1': 0.5, 'sigma1': 0.5, 'mu2': 2.0, 'sigma2': 2.0}
    for key, tolerance in tolerances.items():
        assert abs(res[key] - reference_fit[key]) <= tolerance, \
            f'{key}={res[key]} does not match the independently fitted value {reference_fit[key]}.'


def test_wasserstein_was_computed_from_100000_generated_samples():
    res = load_results()
    with open(RUNTIME_FILE, 'r') as f:
        runtime = json.load(f)
    matching = []
    for call in runtime['wasserstein']:
        correct_inputs = (
            (call['u_is_empirical'] and call['v_len'] == 100000) or
            (call['v_is_empirical'] and call['u_len'] == 100000)
        )
        if correct_inputs and abs(call['value'] - res['wasserstein_distance']) <= 1e-5:
            matching.append(call)
    assert matching, ('The reported Wasserstein distance was not produced by scipy.stats.'
                      'wasserstein_distance using the empirical data and 100,000 synthetic samples.')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
