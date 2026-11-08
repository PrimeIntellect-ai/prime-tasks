#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest


def test_venv_and_packages():
    """Test that the virtual environment is created and required packages are installed."""
    python_path = '/home/user/ml_env/bin/python'
    assert os.path.isfile(python_path), f"Virtual environment python not found at {python_path}. Did you create the venv?"

    result = subprocess.run([python_path, '-m', 'pip', 'freeze'], capture_output=True, text=True)
    installed_packages = result.stdout.lower()

    assert 'numpy' in installed_packages, "numpy is not installed in the virtual environment."
    assert 'pandas' in installed_packages, "pandas is not installed in the virtual environment."
    assert 'scipy' in installed_packages, "scipy is not installed in the virtual environment."


def load_output():
    file_path = '/home/user/training_features.json'
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."
    with open(file_path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")


def recompute_expected_features():
    """Derive expected features from the supplied sensor data and baseline."""
    sensor_path = '/home/user/data/sensor_readings.csv'
    baseline_path = '/home/user/data/baseline.json'
    assert os.path.isfile(sensor_path), f"Missing source data: {sensor_path}"
    assert os.path.isfile(baseline_path), f"Missing baseline data: {baseline_path}"

    frame = pd.read_csv(sensor_path)
    assert 'time' in frame.columns
    assert len(frame) >= 2

    time = frame['time'].to_numpy(dtype=float)
    intervals = np.diff(time)
    assert np.all(intervals > 0), "Time values must be strictly increasing."
    dt = float(intervals[0])
    assert np.allclose(intervals, dt, rtol=1e-7, atol=1e-12), "Sampling must be uniform."

    dominant = {}
    for seg_idx in range(4):
        columns = [f'x_{i}' for i in range(seg_idx * 25, (seg_idx + 1) * 25)]
        assert all(column in frame.columns for column in columns)
        signal = frame[columns].mean(axis=1).to_numpy(dtype=float)
        amplitudes = np.abs(np.fft.rfft(signal))
        frequencies = np.fft.rfftfreq(signal.size, d=dt)
        peak_index = int(np.argmax(amplitudes[1:])) + 1
        dominant[f'seg_{seg_idx}'] = round(float(frequencies[peak_index]), 1)

    with open(baseline_path, 'r') as f:
        baseline = json.load(f)

    differences = {
        key: round(abs(value - float(baseline[key])), 1)
        for key, value in dominant.items()
    }
    analytical = abs(dominant['seg_1'] - 12.5) <= 1.0
    return dominant, analytical, differences


def test_training_features_output():
    """Test that the output JSON has the required structure and expected values."""
    data = load_output()

    assert "dominant_frequencies" in data, "Missing 'dominant_frequencies' in output JSON."
    assert "is_valid_analytical" in data, "Missing 'is_valid_analytical' in output JSON."
    assert "baseline_differences" in data, "Missing 'baseline_differences' in output JSON."

    assert data["is_valid_analytical"] is True, "'is_valid_analytical' should be true based on the calculated dominant frequency of seg_1."

    expected_freqs = {
        "seg_0": 5.0,
        "seg_1": 12.5,
        "seg_2": 20.0,
        "seg_3": 35.0
    }
    for k, v in expected_freqs.items():
        assert k in data["dominant_frequencies"], f"Missing {k} in dominant_frequencies."
        actual_freq = data["dominant_frequencies"][k]
        assert isinstance(actual_freq, (int, float)), f"Dominant frequency for {k} must be a number."
        assert abs(actual_freq - v) < 0.05, f"Incorrect dominant frequency for {k}. Expected {v}, got {actual_freq}."

    expected_diffs = {
        "seg_0": 0.0,
        "seg_1": 0.5,
        "seg_2": 0.5,
        "seg_3": 1.0
    }
    for k, v in expected_diffs.items():
        assert k in data["baseline_differences"], f"Missing {k} in baseline_differences."
        actual_diff = data["baseline_differences"][k]
        assert isinstance(actual_diff, (int, float)), f"Baseline difference for {k} must be a number."
        assert abs(actual_diff - v) < 0.05, f"Incorrect baseline difference for {k}. Expected {v}, got {actual_diff}."


def test_features_match_source_data_and_baseline():
    """Independently recompute FFT features and baseline differences from the inputs."""
    data = load_output()
    expected_freqs, expected_analytical, expected_diffs = recompute_expected_features()

    assert data.get('is_valid_analytical') is expected_analytical
    for key in ('seg_0', 'seg_1', 'seg_2', 'seg_3'):
        assert key in data.get('dominant_frequencies', {})
        assert key in data.get('baseline_differences', {})
        assert abs(data['dominant_frequencies'][key] - expected_freqs[key]) < 0.05, (
            f"Dominant frequency for {key} does not match the FFT of sensor_readings.csv."
        )
        assert abs(data['baseline_differences'][key] - expected_diffs[key]) < 0.05, (
            f"Baseline difference for {key} does not match baseline.json."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
