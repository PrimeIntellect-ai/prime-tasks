#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp, simpson
from scipy.optimize import least_squares, minimize

RESULTS_PATH = '/home/user/results.json'
DATA_PATH = '/home/user/experiment_data.csv'
EXPECTED_KEYS = {"a", "b", "c", "d", "optimal_x0", "optimal_y0", "max_integral"}


def simulate(params, z0, times):
    a, b, c, d = params

    def rhs(t, z):
        x, y = z
        return [-a * x + b * y, c * x - d * y * y]

    sol = solve_ivp(
        rhs,
        (float(times[0]), float(times[-1])),
        z0,
        t_eval=times,
        method='DOP853',
        rtol=1e-10,
        atol=1e-12,
    )
    assert sol.success and sol.y.shape == (2, len(times)), 'ODE simulation failed.'
    assert np.all(np.isfinite(sol.y)), 'ODE simulation produced non-finite values.'
    return sol.y.T


def fit_reference(data):
    times = data['t'].to_numpy(dtype=float)
    observed = data[['x', 'y']].to_numpy(dtype=float)

    def residuals(params):
        try:
            return (simulate(params, [1.0, 2.0], times) - observed).ravel()
        except Exception:
            return np.full(observed.size, 1e6)

    starts = [
        [0.5, 0.2, 0.8, 0.3],
        [1.0, 1.0, 1.0, 1.0],
        [0.25, 0.75, 1.25, 0.5],
        [1.5, 0.25, 0.5, 1.0],
    ]
    fits = [
        least_squares(
            residuals,
            start,
            bounds=(np.zeros(4), np.full(4, 2.0)),
            xtol=1e-11,
            ftol=1e-11,
            gtol=1e-11,
            max_nfev=3000,
        )
        for start in starts
    ]
    best = min(fits, key=lambda fit: float(np.dot(fit.fun, fit.fun)))
    assert best.success, 'Independent curve fitting failed.'
    return best.x, float(np.dot(best.fun, best.fun)), residuals


def total_integral(params, z0):
    times = np.linspace(0.0, 10.0, 1001)
    trajectory = simulate(params, z0, times)
    return float(simpson(trajectory[:, 0] + trajectory[:, 1], x=times))


def optimize_initial_conditions(params):
    def objective(z0):
        return -total_integral(params, z0)

    candidates = [np.array([5.0, 5.0])]
    for start in ([2.5, 2.5], [0.0, 0.0], [5.0, 0.0], [0.0, 5.0]):
        result = minimize(
            objective,
            start,
            method='L-BFGS-B',
            bounds=[(0.0, 5.0), (0.0, 5.0)],
            options={'ftol': 1e-12, 'gtol': 1e-9, 'maxiter': 300},
        )
        if result.success and np.all(np.isfinite(result.x)):
            candidates.append(np.clip(result.x, 0.0, 5.0))

    best_z0 = max(candidates, key=lambda z: total_integral(params, z))
    return best_z0, total_integral(params, best_z0)


def load_results():
    assert os.path.exists(RESULTS_PATH), f'File {RESULTS_PATH} does not exist.'
    assert os.path.isfile(RESULTS_PATH), f'{RESULTS_PATH} is not a file.'
    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'{RESULTS_PATH} is not a valid JSON file.') from exc

    assert isinstance(results, dict), 'results.json must contain a JSON object.'
    actual_keys = set(results.keys())
    assert EXPECTED_KEYS.issubset(actual_keys), \
        f'Missing keys in JSON. Expected {EXPECTED_KEYS}, found {actual_keys}.'
    for key in EXPECTED_KEYS:
        value = results[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f'{key} must be numeric.'
        assert math.isfinite(float(value)), f'{key} must be finite.'
    return results


def test_results_json_exists():
    assert os.path.exists(RESULTS_PATH), f'File {RESULTS_PATH} does not exist.'
    assert os.path.isfile(RESULTS_PATH), f'{RESULTS_PATH} is not a file.'


def test_results_json_structure_and_values():
    results = load_results()

    # Preserve the original parameter and initial-condition sanity assertions.
    assert math.isclose(results['a'], 0.5, abs_tol=0.05), \
        f"Parameter 'a' is incorrect. Expected ~0.5, got {results['a']}."
    assert math.isclose(results['b'], 0.2, abs_tol=0.05), \
        f"Parameter 'b' is incorrect. Expected ~0.2, got {results['b']}."
    assert math.isclose(results['c'], 0.8, abs_tol=0.05), \
        f"Parameter 'c' is incorrect. Expected ~0.8, got {results['c']}."
    assert math.isclose(results['d'], 0.3, abs_tol=0.05), \
        f"Parameter 'd' is incorrect. Expected ~0.3, got {results['d']}."
    assert math.isclose(results['optimal_x0'], 5.0, abs_tol=0.05), \
        f"'optimal_x0' is incorrect. Expected ~5.0, got {results['optimal_x0']}."
    assert math.isclose(results['optimal_y0'], 5.0, abs_tol=0.05), \
        f"'optimal_y0' is incorrect. Expected ~5.0, got {results['optimal_y0']}."

    data = pd.read_csv(DATA_PATH)
    assert {'t', 'x', 'y'}.issubset(data.columns), 'Experimental CSV has invalid columns.'
    reference_params, reference_sse, residual_fn = fit_reference(data)
    submitted_params = np.array(
        [results['a'], results['b'], results['c'], results['d']], dtype=float
    )
    assert np.all((submitted_params >= 0.0) & (submitted_params <= 2.0)), \
        'Fitted parameters must be within [0, 2].'

    # Compare with a fit recomputed from the supplied observations and verify its SSE.
    assert np.allclose(submitted_params, reference_params, atol=0.01, rtol=0.0), \
        f'Submitted parameters do not match the independently recomputed fit {reference_params}.'
    submitted_residuals = residual_fn(submitted_params)
    submitted_sse = float(np.dot(submitted_residuals, submitted_residuals))
    assert submitted_sse <= reference_sse + 5e-4, \
        f'Submitted parameter SSE {submitted_sse} is worse than fitted SSE {reference_sse}.'

    reference_z0, reference_integral = optimize_initial_conditions(reference_params)
    submitted_z0 = np.array(
        [results['optimal_x0'], results['optimal_y0']], dtype=float
    )
    assert np.all((submitted_z0 >= 0.0) & (submitted_z0 <= 5.0)), \
        'Optimal initial conditions must be within [0, 5].'
    assert np.allclose(submitted_z0, reference_z0, atol=0.05, rtol=0.0), \
        f'Submitted initial conditions are not optimal; expected approximately {reference_z0}.'

    # Recompute the integral rather than accepting an arbitrary value from a broad range.
    submitted_integral = total_integral(submitted_params, submitted_z0)
    assert math.isclose(results['max_integral'], submitted_integral, abs_tol=0.05), \
        f"Reported max_integral {results['max_integral']} does not equal the simulated integral {submitted_integral}."
    assert math.isclose(results['max_integral'], reference_integral, abs_tol=0.12), \
        f"Reported max_integral {results['max_integral']} does not match the independently optimized value {reference_integral}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
