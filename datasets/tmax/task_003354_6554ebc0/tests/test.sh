#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import numpy as np
from scipy.optimize import brentq
from scipy.special import logsumexp
from scipy.stats import wasserstein_distance


def trusted_expected_values():
    x = np.arange(1, 101, dtype=float)

    target_log = 20.0 * math.log(10.0)
    alpha = brentq(
        lambda a: logsumexp(a * np.sqrt(x)) - target_log,
        0.0,
        10.0,
        xtol=1e-14,
    )

    log_q = alpha * np.sqrt(x)
    log_q -= logsumexp(log_q)
    q = np.exp(log_q)

    # Independently reconstruct the empirical distribution created by setup.py,
    # including the precision with which it was written to empirical.csv.
    rng = np.random.RandomState(42)
    empirical_logits = 4.65 * np.sqrt(x)
    empirical_logits -= np.max(empirical_logits)
    p_unnorm = np.exp(empirical_logits) * (1.0 + 0.1 * rng.randn(100))
    p_unnorm = np.clip(p_unnorm, 1e-10, None)
    p = p_unnorm / np.sum(p_unnorm)
    p = np.array([float(f'{value:.10e}') for value in p], dtype=float)

    kl_divergence = np.sum(p * (np.log(p) - log_q))
    wasserstein = wasserstein_distance(x, x, u_weights=p, v_weights=q)

    return {
        'alpha': round(float(alpha), 6),
        'kl_divergence': round(float(kl_divergence), 6),
        'wasserstein_distance': round(float(wasserstein), 6),
    }


def test_results_json_exists():
    file_path = '/home/user/results.json'
    assert os.path.isfile(file_path), f'File {file_path} is missing.'


def test_results_json_content():
    file_path = '/home/user/results.json'
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {file_path} is not valid JSON.'

    expected_keys = {'alpha', 'kl_divergence', 'wasserstein_distance'}
    assert set(data.keys()) == expected_keys, f'Expected keys {expected_keys}, got {set(data.keys())}'

    expected_values = trusted_expected_values()
    for key, expected in expected_values.items():
        actual = data[key]
        assert isinstance(actual, (int, float)), f'Value for {key} must be a number, got {type(actual)}'
        assert math.isclose(actual, expected, abs_tol=1e-4), \
            f'Expected {key} to be close to {expected}, got {actual}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
