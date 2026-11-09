#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import numpy as np
import pytest

def test_params_json_exists():
    """Check if the parameters JSON file was created."""
    assert os.path.exists('/home/user/params.json'), "The file /home/user/params.json does not exist."

def test_metric_mse():
    """Calculate the MSE of the reconstructed waveform and assert it's within the threshold."""
    params_path = '/home/user/params.json'
    assert os.path.exists(params_path), f"Cannot evaluate metric: {params_path} is missing."

    with open(params_path, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {params_path} is not valid JSON.")

    assert "A" in params, "Key 'A' missing in params.json."
    assert "gamma" in params, "Key 'gamma' missing in params.json."
    assert "f" in params, "Key 'f' missing in params.json."

    A = float(params["A"])
    gamma = float(params["gamma"])
    f_val = float(params["f"])

    # Ground truth
    A_true = 0.85
    gamma_true = 2.5
    f_true = 440.0
    sample_rate = 8000
    num_samples = 4000

    t = np.arange(num_samples) / sample_rate
    y_true = A_true * np.exp(-gamma_true * t) * np.sin(2 * np.pi * f_true * t)
    y_pred = A * np.exp(-gamma * t) * np.sin(2 * np.pi * f_val * t)

    mse = np.mean((y_true - y_pred)**2)
    threshold = 1e-4

    assert mse <= threshold, f"MSE {mse:.6e} is greater than the threshold {threshold:.6e}."

def test_c_tool_compiled():
    """Check if the C tool was compiled."""
    assert os.path.exists('/app/tools/wav2csv'), "The compiled executable /app/tools/wav2csv does not exist."
    assert os.access('/app/tools/wav2csv', os.X_OK), "The file /app/tools/wav2csv is not executable."

def test_csv_generated():
    """Check if the CSV file was generated."""
    assert os.path.exists('/home/user/signal.csv'), "The file /home/user/signal.csv does not exist."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
