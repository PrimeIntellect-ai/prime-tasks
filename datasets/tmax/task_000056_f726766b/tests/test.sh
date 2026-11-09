#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import numpy as np
import scipy.io.wavfile as wav
from scipy.integrate import solve_ivp
import pytest

def test_parameters_json_exists():
    """Test that the parameters.json file exists."""
    file_path = "/home/user/parameters.json"
    assert os.path.exists(file_path), f"File not found: {file_path}"
    assert os.path.isfile(file_path), f"Path is not a file: {file_path}"

def test_parameters_keys():
    """Test that the parameters.json file has the correct keys and float values."""
    file_path = "/home/user/parameters.json"
    assert os.path.exists(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_keys = {"c1", "c2", "k1", "k2", "k3"}
    assert set(params.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, found {set(params.keys())}."

    for k in expected_keys:
        assert isinstance(params[k], (int, float)), f"Parameter {k} must be a number, found {type(params[k])}."

def test_model_fit_mse():
    """Test that the simulated x1(t) with the estimated parameters matches the audio data with MSE <= 1e-4."""
    file_path = "/home/user/parameters.json"
    assert os.path.exists(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        params = json.load(f)

    c1 = float(params["c1"])
    c2 = float(params["c2"])
    k1 = float(params["k1"])
    k2 = float(params["k2"])
    k3 = float(params["k3"])

    # Load audio data
    audio_path = "/app/vibration_data.wav"
    assert os.path.exists(audio_path), f"Audio file missing: {audio_path}"

    sample_rate, x1_audio_data = wav.read(audio_path)
    assert sample_rate == 1000, f"Expected sample rate 1000, got {sample_rate}"
    assert len(x1_audio_data) == 10000, f"Expected 10000 samples, got {len(x1_audio_data)}"

    # Simulate ODE
    def system(t, y):
        x1, x2, v1, v2 = y
        m1, m2 = 1.0, 1.5

        a1 = (-c1*v1 - (k1+k2)*x1 + k2*x2) / m1
        a2 = (-c2*v2 - (k2+k3)*x2 + k2*x1) / m2
        return [v1, v2, a1, a2]

    t_span = (0, 10)
    t_eval = np.linspace(0, 10, 10000, endpoint=False)
    y0 = [1.0, 0.0, 0.0, 0.0]

    sol = solve_ivp(system, t_span, y0, t_eval=t_eval, method='Radau', rtol=1e-8, atol=1e-8)

    assert sol.success, "ODE simulation failed with the provided parameters."

    x1_simulated = sol.y[0]

    # Ensure types match for MSE calculation
    x1_audio_data = x1_audio_data.astype(np.float64)
    x1_simulated = x1_simulated.astype(np.float64)

    mse = np.mean((x1_simulated - x1_audio_data) ** 2)

    threshold = 1e-4
    assert mse <= threshold, f"MSE {mse:.3e} is greater than threshold {threshold:.3e}. Model fit is not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
