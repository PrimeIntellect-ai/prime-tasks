#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import subprocess
import sys

import numpy as np
import pandas as pd
from scipy.stats import wasserstein_distance

PIPELINE = '/home/user/synthetic_pipeline.py'
TEST_PIPELINE = '/home/user/test_pipeline.py'
METRICS = '/home/user/metrics.json'
DATA = '/home/user/original_data.csv'


def test_files_exist():
    """Check that the required files have been created."""
    assert os.path.isfile(PIPELINE), "synthetic_pipeline.py is missing."
    assert os.path.isfile(TEST_PIPELINE), "test_pipeline.py is missing."
    assert os.path.isfile(METRICS), "metrics.json is missing."


def test_execute_pipeline_and_recompute_metrics():
    """Execute the submitted pipeline and independently verify its results."""
    # Ensure the input data was not replaced or modified by the submission.
    np.random.seed(10)
    expected_data = np.random.multivariate_normal(
        [1.0, -1.0, 2.5],
        [[1.0, 0.4, 0.1], [0.4, 1.5, -0.3], [0.1, -0.3, 2.0]],
        100,
    )
    original_df = pd.read_csv(DATA)
    assert list(original_df.columns) == ['A', 'B', 'C']
    assert original_df.shape == (100, 3)
    np.testing.assert_allclose(original_df.to_numpy(), expected_data, rtol=0, atol=1e-12)

    # Replace any precomputed output, then require the artifact itself to create it.
    with open(METRICS, 'w') as f:
        f.write('verifier sentinel: pipeline did not replace this file')
    result = subprocess.run(
        [sys.executable, PIPELINE],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"synthetic_pipeline.py failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(METRICS), "Pipeline did not create metrics.json."

    with open(METRICS) as f:
        actual = json.load(f)

    values = original_df.to_numpy(dtype=float)
    mean = values.mean(axis=0)
    cov = np.cov(values, rowvar=False, ddof=1)
    chol = np.linalg.cholesky(cov)
    inv_cov = np.linalg.inv(cov)

    def log_target(x):
        delta = x - mean
        return -0.5 * float(delta @ inv_cov @ delta)

    def reference_chain(always_draw_uniform):
        np.random.seed(42)
        current = mean.copy()
        samples = []
        for _ in range(2500):
            proposal = current + 0.5 * (chol @ np.random.standard_normal(3))
            log_ratio = log_target(proposal) - log_target(current)
            if always_draw_uniform:
                if np.random.random() < min(1.0, np.exp(log_ratio)):
                    current = proposal
            else:
                # This is an equivalent MH implementation that accepts uphill
                # proposals without unnecessarily consuming a random draw.
                if log_ratio >= 0 or np.random.random() < np.exp(log_ratio):
                    current = proposal
            samples.append(current.copy())
        return np.asarray(samples[500:])

    def candidate_metrics(synth, bootstrap_order):
        distances = [wasserstein_distance(values[:, j], synth[:, j]) for j in range(3)]
        boot = [[] for _ in range(3)]
        n = len(synth)

        if bootstrap_order == 'rows':
            np.random.seed(123)
            for _ in range(100):
                resampled = synth[np.random.choice(n, size=n, replace=True)]
                for j in range(3):
                    boot[j].append(wasserstein_distance(values[:, j], resampled[:, j]))
        elif bootstrap_order == 'features':
            np.random.seed(123)
            for j in range(3):
                for _ in range(100):
                    resampled = synth[np.random.choice(n, size=n, replace=True), j]
                    boot[j].append(wasserstein_distance(values[:, j], resampled))
        elif bootstrap_order == 'reset_each_feature':
            for j in range(3):
                np.random.seed(123)
                for _ in range(100):
                    resampled = synth[np.random.choice(n, size=n, replace=True), j]
                    boot[j].append(wasserstein_distance(values[:, j], resampled))

        result = {}
        for j, feature in enumerate(['A', 'B', 'C']):
            lower, upper = np.percentile(boot[j], [2.5, 97.5])
            result[feature] = {
                'distance': float(distances[j]),
                'ci_lower': float(lower),
                'ci_upper': float(upper),
            }
        return result

    candidates = []
    for uniform_mode in (True, False):
        synth = reference_chain(uniform_mode)
        assert synth.shape == (2000, 3)
        for order in ('rows', 'features', 'reset_each_feature'):
            candidates.append(candidate_metrics(synth, order))

    def matches(candidate):
        try:
            for feature in ('A', 'B', 'C'):
                for key in ('distance', 'ci_lower', 'ci_upper'):
                    value = actual[feature][key]
                    if isinstance(value, bool) or not np.isfinite(value):
                        return False
                    if not np.isclose(value, candidate[feature][key], rtol=1e-9, atol=1e-10):
                        return False
            return True
        except (KeyError, TypeError, ValueError):
            return False

    assert any(matches(candidate) for candidate in candidates), (
        "metrics.json does not match independently recomputed MCMC distances and "
        "100-iteration bootstrap confidence intervals."
    )

    # Confirm execution did not modify the fixed input dataset.
    after = pd.read_csv(DATA).to_numpy()
    np.testing.assert_allclose(after, expected_data, rtol=0, atol=1e-12)


def test_metrics_json_structure():
    """Check that metrics.json has the correct structure and types."""
    metrics_path = METRICS
    if not os.path.isfile(metrics_path):
        return  # handled by test_files_exist

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, "metrics.json is not a valid JSON file."

    expected_keys = {"A", "B", "C"}
    assert set(metrics.keys()) == expected_keys, f"Expected keys {expected_keys} in metrics.json, got {set(metrics.keys())}."

    for feature in expected_keys:
        feature_data = metrics[feature]
        assert isinstance(feature_data, dict), f"Value for {feature} should be a dictionary."

        expected_subkeys = {"distance", "ci_lower", "ci_upper"}
        assert set(feature_data.keys()) == expected_subkeys, f"Expected keys {expected_subkeys} in {feature}, got {set(feature_data.keys())}."

        for subkey in expected_subkeys:
            val = feature_data[subkey]
            assert isinstance(val, (int, float)), f"Value for {feature}.{subkey} should be a number, got {type(val)}."


def test_calculate_wasserstein_behavior():
    """Exercise the required function on verifier-selected inputs."""
    spec = importlib.util.spec_from_file_location('submitted_synthetic_pipeline', PIPELINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'calculate_wasserstein')
    assert module.calculate_wasserstein([1, 2, 3], [1, 2, 3]) == 0.0
    expected = wasserstein_distance([0, 0, 10], [0, 5, 10])
    actual = module.calculate_wasserstein([0, 0, 10], [0, 5, 10])
    assert np.isclose(actual, expected, rtol=1e-12, atol=1e-12)


def test_test_pipeline_content():
    """Check that test_pipeline.py contains an import for calculate_wasserstein and pytest assertions."""
    test_path = TEST_PIPELINE
    if not os.path.isfile(test_path):
        return

    with open(test_path, 'r') as f:
        content = f.read()

    assert 'calculate_wasserstein' in content, "test_pipeline.py must import/use calculate_wasserstein."
    assert 'assert ' in content, "test_pipeline.py must contain pytest assertions."


def test_test_pipeline_passes():
    """Run pytest on test_pipeline.py and ensure it passes."""
    test_path = TEST_PIPELINE
    if not os.path.isfile(test_path):
        return

    result = subprocess.run([sys.executable, '-m', 'pytest', test_path], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"pytest on {test_path} failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
