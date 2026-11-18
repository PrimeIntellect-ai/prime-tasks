#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sys
import subprocess
import pytest

def get_expected_results():
    """
    Computes the expected results by running a subprocess that uses the required
    third-party libraries. This avoids importing them directly in the test file,
    adhering to the stdlib-only rule for the test suite itself.
    """
    script = """
import json
import pandas as pd
import numpy as np
from scipy.spatial.distance import mahalanobis
from scipy.stats import ttest_ind
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

try:
    df = pd.read_csv('/home/user/raw_data.csv')
    X = df[['f1', 'f2', 'f3', 'f4', 'f5']].values
    y = df['y'].values

    # Step 1
    cov_matrix = np.cov(X, rowvar=False)
    inv_cov_matrix = np.linalg.inv(cov_matrix)
    mean_dist = np.mean(X, axis=0)

    distances = []
    for i in range(len(X)):
        dist = mahalanobis(X[i], mean_dist, inv_cov_matrix)
        distances.append(dist)

    distances = np.array(distances)
    mask = distances <= 15.0

    X_clean = X[mask]
    y_clean = y[mask]

    outliers_removed = len(y) - len(y_clean)

    # Step 2
    res = ttest_ind(y, y_clean, equal_var=False)
    t_stat = res.statistic
    p_val = res.pvalue
    ci = res.confidence_interval(confidence_level=0.95)

    # Step 3
    param_grid = {'alpha': [0.01, 0.1, 1.0, 10.0, 100.0]}
    ridge = Ridge()
    grid = GridSearchCV(ridge, param_grid, cv=5, scoring='neg_mean_squared_error')
    grid.fit(X_clean, y_clean)
    best_alpha = grid.best_params_['alpha']

    expected = {
        "outliers_removed": int(outliers_removed),
        "t_statistic": round(float(t_stat), 4),
        "p_value": round(float(p_val), 4),
        "ci_lower": round(float(ci.low), 4),
        "ci_upper": round(float(ci.high), 4),
        "best_alpha": float(best_alpha)
    }
    print(json.dumps(expected))
except Exception as e:
    print(json.dumps({"error": str(e)}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected results using third-party libs. Stderr: {result.stderr}")

    try:
        data = json.loads(result.stdout)
        if "error" in data:
            pytest.fail(f"Error computing expected results: {data['error']}")
        return data
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse expected results JSON. Stdout: {result.stdout}")

def test_results_json_exists_and_valid():
    """Test that results.json exists and is valid JSON."""
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"The file {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} is not valid JSON.")

def test_results_correctness():
    """Test that the computed results match the expected ground truth."""
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"The file {results_path} does not exist."

    with open(results_path, "r") as f:
        results = json.load(f)

    expected = get_expected_results()

    # Check keys
    expected_keys = ["outliers_removed", "t_statistic", "p_value", "ci_lower", "ci_upper", "best_alpha"]
    for key in expected_keys:
        assert key in results, f"Key '{key}' is missing from {results_path}."

    # Check values
    assert results["outliers_removed"] == expected["outliers_removed"], \
        f"Incorrect 'outliers_removed'. Expected {expected['outliers_removed']}, got {results['outliers_removed']}."

    assert abs(results["t_statistic"] - expected["t_statistic"]) <= 1e-3, \
        f"Incorrect 't_statistic'. Expected {expected['t_statistic']}, got {results['t_statistic']}."

    assert abs(results["p_value"] - expected["p_value"]) <= 1e-3, \
        f"Incorrect 'p_value'. Expected {expected['p_value']}, got {results['p_value']}."

    assert abs(results["ci_lower"] - expected["ci_lower"]) <= 1e-3, \
        f"Incorrect 'ci_lower'. Expected {expected['ci_lower']}, got {results['ci_lower']}."

    assert abs(results["ci_upper"] - expected["ci_upper"]) <= 1e-3, \
        f"Incorrect 'ci_upper'. Expected {expected['ci_upper']}, got {results['ci_upper']}."

    assert results["best_alpha"] == expected["best_alpha"], \
        f"Incorrect 'best_alpha'. Expected {expected['best_alpha']}, got {results['best_alpha']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
