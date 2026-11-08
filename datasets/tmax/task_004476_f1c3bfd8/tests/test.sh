#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import GridSearchCV, train_test_split

ARTIFACT = '/home/user/artifacts/experiment_summary.json'
DATASET = '/home/user/data/server_metrics.csv'


def test_artifacts_directory_exists():
    assert os.path.isdir('/home/user/artifacts'), "The /home/user/artifacts directory was not created."


def test_experiment_summary_exists():
    assert os.path.isfile(ARTIFACT), "The experiment_summary.json file is missing."


def test_experiment_summary_format():
    with open(ARTIFACT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("experiment_summary.json is not a valid JSON file.")

    assert "best_params" in data, "Missing 'best_params' in JSON output."
    assert "test_mse_ci_lower" in data, "Missing 'test_mse_ci_lower' in JSON output."
    assert "test_mse_ci_upper" in data, "Missing 'test_mse_ci_upper' in JSON output."

    assert isinstance(data["best_params"], dict), "'best_params' should be a dictionary."
    assert "max_depth" in data["best_params"], "Missing 'max_depth' in best_params."
    assert "n_estimators" in data["best_params"], "Missing 'n_estimators' in best_params."

    assert isinstance(data["test_mse_ci_lower"], (int, float)), "'test_mse_ci_lower' should be a number."
    assert isinstance(data["test_mse_ci_upper"], (int, float)), "'test_mse_ci_upper' should be a number."
    assert data["test_mse_ci_lower"] <= data["test_mse_ci_upper"], "Lower CI bound should be less than or equal to upper CI bound."


def test_experiment_summary_values():
    with open(ARTIFACT, 'r') as f:
        data = json.load(f)

    best_params = data["best_params"]
    assert best_params["max_depth"] in [3, 5, None], f"Invalid max_depth value: {best_params['max_depth']}"
    assert best_params["n_estimators"] in [10, 50, 100], f"Invalid n_estimators value: {best_params['n_estimators']}"

    assert data["test_mse_ci_lower"] > 0, "MSE CI lower bound must be positive."
    assert data["test_mse_ci_upper"] > 0, "MSE CI upper bound must be positive."


def _canonical_dataset():
    np.random.seed(123)
    n_samples = 1000
    cpu_load = np.random.uniform(0, 100, n_samples)
    memory_usage = np.random.uniform(1, 16, n_samples)
    network_io = np.random.exponential(100, n_samples)
    nan_indices = np.random.choice(n_samples, size=50, replace=False)
    memory_usage[nan_indices] = np.nan
    response_time = (
        10
        + 0.5 * cpu_load
        + 2.0 * np.nan_to_num(memory_usage, nan=8.0)
        + 0.05 * network_io
        + np.random.normal(0, 5, n_samples)
    )
    outlier_indices = np.random.choice(n_samples, size=15, replace=False)
    response_time[outlier_indices] += np.random.uniform(500, 1000, size=15)
    return pd.DataFrame({
        'cpu_load': cpu_load,
        'memory_usage': memory_usage,
        'network_io': network_io,
        'response_time': response_time,
    })


def test_summary_matches_required_pipeline():
    assert os.path.isfile(DATASET), "The server metrics dataset is missing."
    actual_df = pd.read_csv(DATASET)
    canonical_df = _canonical_dataset()
    pd.testing.assert_frame_equal(
        actual_df,
        canonical_df,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )

    df = actual_df.copy()
    df['memory_usage'] = df['memory_usage'].fillna(df['memory_usage'].median())
    cutoff = df['response_time'].quantile(0.99)
    df = df[df['response_time'] <= cutoff]

    X = df[['cpu_load', 'memory_usage', 'network_io']]
    y = df['response_time']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    search = GridSearchCV(
        RandomForestRegressor(random_state=42),
        {'n_estimators': [10, 50, 100], 'max_depth': [3, 5, None]},
        cv=3,
    )
    search.fit(X_train, y_train)
    predictions = search.best_estimator_.predict(X_test)

    y_true = y_test.to_numpy()
    rng = np.random.default_rng(42)
    bootstrap_mses = []
    for _ in range(1000):
        indices = rng.integers(0, len(y_true), size=len(y_true))
        bootstrap_mses.append(mean_squared_error(y_true[indices], predictions[indices]))
    expected_lower, expected_upper = np.percentile(bootstrap_mses, [2.5, 97.5])

    with open(ARTIFACT, 'r') as f:
        result = json.load(f)

    assert set(result.keys()) == {'best_params', 'test_mse_ci_lower', 'test_mse_ci_upper'}, "JSON has unexpected or missing top-level keys."
    assert set(result['best_params'].keys()) == {'max_depth', 'n_estimators'}, "best_params has unexpected or missing keys."
    assert result['best_params'] == search.best_params_, "best_params does not match the required GridSearchCV result."
    assert math.isfinite(result['test_mse_ci_lower']), "Lower CI bound must be finite."
    assert math.isfinite(result['test_mse_ci_upper']), "Upper CI bound must be finite."
    assert result['test_mse_ci_lower'] == pytest.approx(float(expected_lower), rel=1e-10, abs=1e-8), "Lower CI bound does not match the required bootstrap computation."
    assert result['test_mse_ci_upper'] == pytest.approx(float(expected_upper), rel=1e-10, abs=1e-8), "Upper CI bound does not match the required bootstrap computation."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
