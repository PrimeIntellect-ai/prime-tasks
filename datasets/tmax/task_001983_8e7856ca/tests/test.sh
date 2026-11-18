#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pytest
import numpy as np
import pandas as pd
from scipy.optimize import minimize, fsolve

def test_results_json_exists():
    assert os.path.isfile('/home/user/results.json'), "The file /home/user/results.json is missing."

def test_results_json_content():
    results_path = '/home/user/results.json'
    if not os.path.isfile(results_path):
        pytest.skip("results.json missing")

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file")

    expected_keys = {"a_0", "b_0", "a_mean", "b_mean", "a_std", "b_std"}
    assert set(results.keys()) == expected_keys, f"results.json keys {set(results.keys())} do not match expected {expected_keys}"

    for k in expected_keys:
        assert isinstance(results[k], (int, float)), f"Value for {k} must be a number"

def test_results_json_values():
    results_path = '/home/user/results.json'
    if not os.path.isfile(results_path):
        pytest.skip("results.json missing")

    with open(results_path, 'r') as f:
        results = json.load(f)

    data_path = "/home/user/data.csv"
    if not os.path.isfile(data_path):
        pytest.skip("data.csv missing")

    df = pd.read_csv(data_path)
    x_data = df['x'].values
    y_data = df['y'].values

    def predict_y(x_arr, a, b):
        y_hat = []
        for x in x_arr:
            func = lambda y: y + np.sin(a * y) - b * x
            sol = fsolve(func, b * x)
            y_hat.append(sol[0])
        return np.array(y_hat)

    def objective(params, x_arr, y_obs):
        a, b = params
        y_hat = predict_y(x_arr, a, b)
        return np.sum((y_obs - y_hat)**2)

    res = minimize(objective, [0.5, 1.0], args=(x_data, y_data))
    a_0, b_0 = res.x

    np.random.seed(42)
    a_list = []
    b_list = []
    for _ in range(100):
        y_syn = y_data + np.random.normal(0, 0.1, len(y_data))
        res_mc = minimize(objective, [a_0, b_0], args=(x_data, y_syn))
        a_list.append(res_mc.x[0])
        b_list.append(res_mc.x[1])

    a_mean = np.mean(a_list)
    b_mean = np.mean(b_list)
    a_std = np.std(a_list, ddof=1)
    b_std = np.std(b_list, ddof=1)

    truth_json = {
        "a_0": round(a_0, 4),
        "b_0": round(b_0, 4),
        "a_mean": round(a_mean, 4),
        "b_mean": round(b_mean, 4),
        "a_std": round(a_std, 4),
        "b_std": round(b_std, 4)
    }

    for key, expected_val in truth_json.items():
        actual_val = results[key]
        assert abs(actual_val - expected_val) <= 0.005, f"Value for {key} is {actual_val}, but expected approximately {expected_val} (within 0.005 tolerance)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
