#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pandas as pd
import numpy as np
import pytest

SENSOR_PATH = '/app/sensor.wav'
PRED_PATH = '/home/user/processed_signal.csv'


def compute_expected():
    assert os.path.isfile(SENSOR_PATH), f"Sensor file {SENSOR_PATH} is missing."
    try:
        output = subprocess.check_output(
            ['sox', SENSOR_PATH, '-t', 'dat', '-'],
            text=True,
            stderr=subprocess.PIPE,
        )
    except Exception as e:
        pytest.fail(f"Failed to extract samples from {SENSOR_PATH}: {e}")

    times = []
    amplitudes = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        parts = line.split()
        times.append(float(parts[0]))
        amplitudes.append(abs(float(parts[1])))

    assert amplitudes, "No audio samples were extracted from the sensor file."

    imputed = []
    last_nonzero = amplitudes[0]
    for amplitude in amplitudes:
        if amplitude == 0.0:
            imputed.append(last_nonzero)
        else:
            imputed.append(amplitude)
            last_nonzero = amplitude

    maximum = max(imputed)
    normalized = [value / maximum for value in imputed]
    smoothed = []
    for i in range(len(normalized)):
        window = normalized[max(0, i - 4):i + 1]
        smoothed.append(sum(window) / len(window))

    return np.asarray(times, dtype=float), np.asarray(smoothed, dtype=float)


def test_processed_signal_exists():
    """Check if the agent correctly created the output file."""
    assert os.path.isfile(PRED_PATH), f"The output file {PRED_PATH} was not found."


def test_processed_signal_mse_and_times():
    """Verify row count, schema, times, and processed amplitudes."""
    expected_times, expected_values = compute_expected()
    assert os.path.isfile(PRED_PATH), f"Prediction file {PRED_PATH} is missing."

    try:
        pred = pd.read_csv(PRED_PATH, header=None)
    except Exception as e:
        pytest.fail(f"Failed to read {PRED_PATH}: {e}")

    assert len(expected_values) == len(pred), (
        f"Length mismatch: expected {len(expected_values)} rows, but got {len(pred)} rows."
    )
    assert len(pred.columns) >= 2, (
        f"Expected at least 2 columns in {PRED_PATH}, found {len(pred.columns)}."
    )
    assert len(pred.columns) == 2, (
        f"Expected exactly 2 columns in {PRED_PATH}, found {len(pred.columns)}."
    )

    try:
        pred_times = pd.to_numeric(pred.iloc[:, 0], errors='raise').to_numpy(dtype=float)
        pred_values = pd.to_numeric(pred.iloc[:, 1], errors='raise').to_numpy(dtype=float)
    except Exception as e:
        pytest.fail(f"Both CSV columns must contain numeric values: {e}")

    assert np.all(np.isfinite(pred_times)), "The time column contains non-finite values."
    assert np.all(np.isfinite(pred_values)), "The amplitude column contains non-finite values."
    assert np.allclose(pred_times, expected_times, rtol=0.0, atol=5e-13), (
        "The time column does not match the sample times extracted from the WAV file."
    )

    mse = np.mean((expected_values - pred_values) ** 2)
    assert mse <= 1e-5, (
        f"MSE {mse:.8f} exceeds threshold of 1e-5. The output values do not match "
        "the expected smoothed normalized amplitude closely enough."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
