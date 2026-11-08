#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import numpy as np

def test_model_params_json_exists():
    assert os.path.isfile("/home/user/model_params.json"), "The file /home/user/model_params.json does not exist."

def test_model_params_keys():
    with open("/home/user/model_params.json", "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/model_params.json is not a valid JSON file."

    expected_keys = {"a", "b", "c", "d"}
    assert expected_keys.issubset(params.keys()), f"JSON file must contain keys {expected_keys}, but found {list(params.keys())}."

    for k in expected_keys:
        assert isinstance(params[k], (int, float)), f"Parameter {k} must be a number."

def test_model_mse_threshold():
    with open("/home/user/model_params.json", "r") as f:
        params = json.load(f)

    a = params['a']
    b = params['b']
    c = params['c']
    d = params['d']

    def true_func(x):
        return 2.5 * np.exp(-0.1 * x) + 4.0 * np.sin(1.5 * x)

    x_val = np.linspace(0, 10, 10000)
    y_true = true_func(x_val)
    y_pred = a * np.exp(b * x_val) + c * np.sin(d * x_val)

    mse = np.mean((y_true - y_pred)**2)
    threshold = 0.05

    assert mse <= threshold, f"Calculated MSE {mse:.6f} exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
