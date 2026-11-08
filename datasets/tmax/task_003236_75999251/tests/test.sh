#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import pytest
import numpy as np
import h5py
import netCDF4 as nc
from scipy import stats


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory not found at {venv_path}"

    # Check for bin/python to ensure it's a valid venv
    python_path = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_path), f"Python executable not found in virtual environment at {python_path}"


def test_analysis_results_json():
    json_path = "/home/user/analysis_results.json"
    assert os.path.isfile(json_path), f"Results JSON file not found at {json_path}"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    expected_keys = {"correlation", "t_statistic", "p_value"}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {actual_keys}"

    with h5py.File("/home/user/data/sim_data.h5", "r") as f:
        sim = np.asarray(f["temperature_field"][:])
    with nc.Dataset("/home/user/data/obs_data.nc", "r") as ds:
        obs_stored = np.asarray(ds.variables["temp_obs"][:])

    assert sim.shape == (100, 100), f"Unexpected simulation data shape: {sim.shape}"
    assert obs_stored.shape == (200, 50), f"Unexpected observational data shape: {obs_stored.shape}"

    # Ensure the supplied inputs were not replaced or altered during the task.
    rng = np.random.RandomState(42)
    original_sim = rng.normal(loc=15.0, scale=3.0, size=(100, 100))
    original_noise = rng.normal(loc=0.5, scale=1.5, size=(100, 100))
    original_obs = original_sim * 0.8 + 3.0 + original_noise
    assert np.array_equal(sim, original_sim), "The supplied simulation dataset was altered"
    assert np.array_equal(obs_stored, original_obs.reshape(200, 50)), "The supplied observational dataset was altered"

    sim_flat = sim.reshape(100, 100).flatten(order="C")
    obs_flat = obs_stored.reshape(100, 100).flatten(order="C")
    correlation = stats.pearsonr(sim_flat, obs_flat).statistic
    t_result = stats.ttest_rel(sim_flat, obs_flat)

    expected_values = {
        "correlation": round(float(correlation), 4),
        "t_statistic": round(float(t_result.statistic), 4),
        "p_value": round(float(t_result.pvalue), 4),
    }

    for key, expected_val in expected_values.items():
        actual_val = data[key]
        assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), \
            f"Value for '{key}' must be a number, got {type(actual_val)}"
        assert math.isfinite(actual_val), f"Value for '{key}' must be finite"
        assert math.isclose(actual_val, expected_val, rel_tol=0.0, abs_tol=1e-4), \
            f"Value for '{key}' is incorrect. Expected ~{expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
