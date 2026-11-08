#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import brentq
from scipy.stats import gaussian_kde

RESULTS_PATH = '/home/user/results.json'
TRAJECTORIES_PATH = '/home/user/trajectories.csv'
REFERENCE_PATH = '/home/user/reference_residuals.csv'


def compute_expected_results():
    df = pd.read_csv(TRAJECTORIES_PATH)
    X = df[['x1', 'x2', 'x3', 'x4', 'x5']].to_numpy(dtype=float)
    X_centered = X - X.mean(axis=0)

    _, _, vt = np.linalg.svd(X_centered, full_matrices=False)
    v1 = vt[0].copy()
    v2 = vt[1].copy()
    z1 = X_centered @ v1
    z2 = X_centered @ v2

    if v1.sum() < 0:
        v1 *= -1
        z1 *= -1
    if v2.sum() < 0:
        v2 *= -1
        z2 *= -1

    coefficients = np.polyfit(z1, z2, 3)
    fitted = np.polyval(coefficients, z1)
    residuals = np.abs(z2 - fitted)

    residual_frame = pd.DataFrame({
        'id': df['id'].to_numpy(),
        'residual': residuals,
    })
    maximum_residuals = residual_frame.groupby('id', sort=True)['residual'].max()

    reference = pd.read_csv(REFERENCE_PATH)['residual'].to_numpy(dtype=float)
    kde = gaussian_kde(reference, bw_method=0.2)

    def quantile_equation(value):
        return kde.integrate_box_1d(-np.inf, value) - 0.95

    spread = max(float(np.std(reference)), 1.0)
    lower = float(np.min(reference) - 10.0 * spread)
    upper = float(np.max(reference) + 10.0 * spread)
    while quantile_equation(lower) >= 0:
        lower -= 10.0 * spread
    while quantile_equation(upper) <= 0:
        upper += 10.0 * spread

    threshold = brentq(quantile_equation, lower, upper, xtol=1e-12, rtol=1e-14)
    divergent_ids = sorted(
        int(trajectory_id)
        for trajectory_id, maximum in maximum_residuals.items()
        if maximum > threshold
    )
    return coefficients, threshold, divergent_ids


def load_results():
    with open(RESULTS_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {RESULTS_PATH} is not valid JSON.')


def test_results_file_exists_and_structure():
    assert os.path.exists(RESULTS_PATH), f'Expected results file at {RESULTS_PATH} does not exist.'
    assert os.path.isfile(RESULTS_PATH), f'Path {RESULTS_PATH} is not a file.'

    results = load_results()
    expected_keys = {'polynomial_coefficients', 'threshold', 'divergent_trajectory_ids'}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f'Missing keys in results.json: {missing_keys}'


def test_results_values():
    results = load_results()

    coeffs = results.get('polynomial_coefficients')
    assert isinstance(coeffs, list), 'polynomial_coefficients must be a list.'
    assert len(coeffs) == 4, f'Expected 4 polynomial_coefficients, got {len(coeffs)}.'
    assert all(isinstance(x, (int, float)) for x in coeffs), 'All polynomial_coefficients must be numbers.'

    threshold = results.get('threshold')
    assert isinstance(threshold, (int, float)), 'threshold must be a number.'
    assert 1.0 < threshold < 5.0, f'threshold {threshold} is outside the expected reasonable range.'

    div_ids = results.get('divergent_trajectory_ids')
    assert isinstance(div_ids, list), 'divergent_trajectory_ids must be a list.'

    expected_div_ids = [2, 7, 14, 23, 31, 38, 45]
    assert div_ids == expected_div_ids, f'Expected divergent_trajectory_ids {expected_div_ids}, but got {div_ids}.'

    expected_coeffs, expected_threshold, recomputed_div_ids = compute_expected_results()
    assert all(math.isfinite(float(x)) for x in coeffs), 'Polynomial coefficients must be finite.'
    assert math.isfinite(float(threshold)), 'threshold must be finite.'
    assert np.allclose(
        np.asarray(coeffs, dtype=float), expected_coeffs, rtol=1e-6, atol=1e-6
    ), f'Polynomial coefficients do not match the SVD projection and cubic OLS fit. Expected {expected_coeffs.tolist()}, got {coeffs}.'
    assert math.isclose(
        float(threshold), float(expected_threshold), rel_tol=1e-6, abs_tol=1e-6
    ), f'threshold does not match the 95th percentile of the required KDE. Expected {expected_threshold}, got {threshold}.'
    assert div_ids == recomputed_div_ids, f'Divergent IDs do not match residual classification. Expected {recomputed_div_ids}, got {div_ids}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
