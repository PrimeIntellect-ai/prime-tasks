#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression, Ridge
from sklearn.model_selection import KFold
from sklearn.metrics import mean_squared_error
from scipy.stats import ttest_rel

def test_condition_txt_exists_and_correct():
    """Verify that condition.txt exists and contains the correct condition number."""
    cond_path = '/home/user/condition.txt'
    x_path = '/home/user/X.csv'

    assert os.path.exists(cond_path), f"Missing file: {cond_path}"
    assert os.path.exists(x_path), f"Missing file: {x_path}"

    # Compute the expected condition number
    X = pd.read_csv(x_path).values
    expected_cond = np.linalg.cond(X.T @ X)

    with open(cond_path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {cond_path} is empty."

    try:
        agent_cond = float(content)
    except ValueError:
        pytest.fail(f"Content of {cond_path} is not a valid float: {content}")

    assert math.isclose(agent_cond, expected_cond, rel_tol=1e-3), \
        f"Condition number incorrect. Expected approx {expected_cond}, got {agent_cond}"

def test_results_json_exists_and_correct():
    """Verify that results.json exists and contains the correct metrics."""
    res_path = '/home/user/results.json'
    x_path = '/home/user/X.csv'
    y_path = '/home/user/y.csv'

    assert os.path.exists(res_path), f"Missing file: {res_path}"
    assert os.path.exists(x_path), f"Missing file: {x_path}"
    assert os.path.exists(y_path), f"Missing file: {y_path}"

    # Load data
    X = pd.read_csv(x_path).values
    y = pd.read_csv(y_path).values.ravel()

    # Recompute expected values
    kf = KFold(n_splits=5, shuffle=True, random_state=123)
    alphas = [0.001, 0.01, 0.1, 1.0, 10.0, 100.0]

    ols_mses = []
    ridge_mses_dict = {a: [] for a in alphas}

    for train_idx, test_idx in kf.split(X):
        X_train, X_test = X[train_idx], X[test_idx]
        y_train, y_test = y[train_idx], y[test_idx]

        lr = LinearRegression()
        lr.fit(X_train, y_train)
        ols_mses.append(mean_squared_error(y_test, lr.predict(X_test)))

        for a in alphas:
            rr = Ridge(alpha=a)
            rr.fit(X_train, y_train)
            ridge_mses_dict[a].append(mean_squared_error(y_test, rr.predict(X_test)))

    mean_ridge = {a: np.mean(mses) for a, mses in ridge_mses_dict.items()}
    expected_opt_alpha = min(mean_ridge, key=mean_ridge.get)
    expected_ols_mse = np.mean(ols_mses)
    expected_ridge_mse = mean_ridge[expected_opt_alpha]

    opt_ridge_mses = ridge_mses_dict[expected_opt_alpha]
    _, expected_p_val = ttest_rel(ols_mses, opt_ridge_mses)

    # Read agent's results
    with open(res_path, 'r') as f:
        try:
            agent_res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {res_path} is not valid JSON.")

    # Check keys
    expected_keys = {"optimal_alpha", "ols_mean_mse", "ridge_mean_mse", "p_value"}
    assert set(agent_res.keys()) == expected_keys, \
        f"JSON keys mismatch. Expected {expected_keys}, got {set(agent_res.keys())}"

    # Check values
    assert math.isclose(agent_res['optimal_alpha'], expected_opt_alpha, rel_tol=1e-3), \
        f"Optimal alpha incorrect. Expected {expected_opt_alpha}, got {agent_res['optimal_alpha']}"

    assert math.isclose(agent_res['ols_mean_mse'], expected_ols_mse, rel_tol=1e-3), \
        f"OLS MSE incorrect. Expected approx {expected_ols_mse}, got {agent_res['ols_mean_mse']}"

    assert math.isclose(agent_res['ridge_mean_mse'], expected_ridge_mse, rel_tol=1e-3), \
        f"Ridge MSE incorrect. Expected approx {expected_ridge_mse}, got {agent_res['ridge_mean_mse']}"

    assert math.isclose(agent_res['p_value'], expected_p_val, rel_tol=1e-3), \
        f"p-value incorrect. Expected approx {expected_p_val}, got {agent_res['p_value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
