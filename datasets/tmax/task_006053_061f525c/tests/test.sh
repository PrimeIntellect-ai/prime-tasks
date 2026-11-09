#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_cluster_params_json_exists():
    """Test that the output JSON file exists."""
    file_path = '/home/user/cluster_params.json'
    assert os.path.exists(file_path), f"The required output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_cluster_params_keys_and_types():
    """Test that the JSON file contains the correct keys and numeric types."""
    file_path = '/home/user/cluster_params.json'
    with open(file_path, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    required_keys = {"mu_x", "mu_y", "sigma", "w"}
    assert isinstance(params, dict), "The JSON root must be a dictionary."

    missing_keys = required_keys - set(params.keys())
    assert not missing_keys, f"Missing required keys in JSON: {missing_keys}"

    for key in required_keys:
        val = params[key]
        assert isinstance(val, (int, float)), f"Value for {key} must be a number, got {type(val)}."

def test_cluster_params_values():
    """Test that the fitted parameters are reasonably close to the true generative parameters."""
    file_path = '/home/user/cluster_params.json'
    with open(file_path, 'r') as f:
        params = json.load(f)

    # True generative parameters used in the setup script
    expected = {
        "mu_x": 65.2,
        "mu_y": 35.8,
        "sigma": 4.5,
        "w": 0.6
    }

    # Tolerances based on typical MLE variance for N=3000
    tolerances = {
        "mu_x": 1.5,
        "mu_y": 1.5,
        "sigma": 1.0,
        "w": 0.1
    }

    for key in expected:
        val = params[key]
        exp = expected[key]
        tol = tolerances[key]
        assert abs(val - exp) <= tol, (
            f"Fitted parameter '{key}' ({val}) is too far from the expected value (~{exp}). "
            f"Difference is {abs(val - exp):.3f}, allowed tolerance is {tol}."
        )

def test_cluster_params_rounded():
    """Test that the parameters are rounded to 3 decimal places."""
    file_path = '/home/user/cluster_params.json'
    with open(file_path, 'r') as f:
        content = f.read()
        params = json.loads(content)

    for key in ["mu_x", "mu_y", "sigma", "w"]:
        # Convert to string to check decimal places
        val_str = str(params[key])
        if '.' in val_str:
            decimals = len(val_str.split('.')[1])
            assert decimals <= 3, f"Parameter '{key}' ({val_str}) has more than 3 decimal places."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
