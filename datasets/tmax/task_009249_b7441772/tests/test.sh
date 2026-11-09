#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import subprocess
import sys
import pytest

def get_expected_values():
    """
    Computes the expected values using a subprocess to avoid importing
    third-party libraries directly in the pytest file.
    """
    script = """
import json
import pandas as pd
import numpy as np
from sklearn.linear_model import BayesianRidge, LinearRegression

df = pd.read_csv('/home/user/sensor_data.csv')
corr = df.corr()
np.fill_diagonal(corr.values, 0)
max_corr_idx = corr.abs().unstack().idxmax()
feat1, feat2 = max_corr_idx

if feat1 < feat2:
    X_col, y_col = feat1, feat2
else:
    X_col, y_col = feat2, feat1

expected_corr = df[X_col].corr(df[y_col])

X = df[[X_col]].values
y = df[y_col].values

br = BayesianRidge()
br.fit(X, y)
expected_bayesian_slope = br.coef_[0]

np.random.seed(42)
n_iterations = 1000
n_size = len(df)
slopes = []

for i in range(n_iterations):
    indices = np.random.choice(n_size, size=n_size, replace=True)
    X_boot = X[indices]
    y_boot = y[indices]
    lr = LinearRegression()
    lr.fit(X_boot, y_boot)
    slopes.append(lr.coef_[0])

expected_lower = np.percentile(slopes, 2.5)
expected_upper = np.percentile(slopes, 97.5)

print(json.dumps({
    "feature_x": X_col,
    "feature_y": y_col,
    "correlation": expected_corr,
    "bayesian_slope_mean": expected_bayesian_slope,
    "bootstrap_slope_lower_95": expected_lower,
    "bootstrap_slope_upper_95": expected_upper
}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

def test_analysis_results():
    results_path = '/home/user/analysis_results.json'
    assert os.path.exists(results_path), f"File {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected = get_expected_values()

    # Check features
    assert agent_data.get('feature_x') == expected['feature_x'], \
        f"Wrong feature_x: expected {expected['feature_x']}, got {agent_data.get('feature_x')}"
    assert agent_data.get('feature_y') == expected['feature_y'], \
        f"Wrong feature_y: expected {expected['feature_y']}, got {agent_data.get('feature_y')}"

    # Check numerical values with tolerances
    corr = agent_data.get('correlation')
    assert corr is not None and abs(corr - expected['correlation']) <= 1e-3, \
        f"Wrong correlation: expected {expected['correlation']:.4f}, got {corr}"

    bayes_slope = agent_data.get('bayesian_slope_mean')
    assert bayes_slope is not None and abs(bayes_slope - expected['bayesian_slope_mean']) <= 1e-3, \
        f"Wrong bayesian slope: expected {expected['bayesian_slope_mean']:.4f}, got {bayes_slope}"

    lower_95 = agent_data.get('bootstrap_slope_lower_95')
    assert lower_95 is not None and abs(lower_95 - expected['bootstrap_slope_lower_95']) <= 0.05, \
        f"Wrong lower bound: expected {expected['bootstrap_slope_lower_95']:.4f}, got {lower_95}"

    upper_95 = agent_data.get('bootstrap_slope_upper_95')
    assert upper_95 is not None and abs(upper_95 - expected['bootstrap_slope_upper_95']) <= 0.05, \
        f"Wrong upper bound: expected {expected['bootstrap_slope_upper_95']:.4f}, got {upper_95}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
