#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def get_expected_frequency():
    """
    Recomputes the expected dominant frequency using standard library math.
    Simulates the trajectory with dt=0.02 and performs a discrete Fourier transform.
    """
    dt = 0.02
    duration = 50.0
    omega = 50.0
    steps = int(duration / dt)

    x, v = 1.0, 0.0
    traj = []
    for _ in range(steps):
        traj.append(x)
        v = v - (omega**2) * x * dt
        x = x + v * dt

    # Perform a partial DFT to find the peak frequency
    # Only search up to the Nyquist frequency (k = steps // 2)
    max_mag = -1.0
    peak_k = 0

    # We can restrict our search to reasonable frequencies (e.g., up to 20 Hz)
    # to save computation time in pure Python. 20 Hz corresponds to k = 20 * duration = 1000
    max_k = min(steps // 2, int(20.0 * duration))

    for k in range(1, max_k + 1):
        re = 0.0
        im = 0.0
        angle = 2.0 * math.pi * k / steps
        for n in range(steps):
            re += traj[n] * math.cos(angle * n)
            im -= traj[n] * math.sin(angle * n)

        mag = re * re + im * im
        if mag > max_mag:
            max_mag = mag
            peak_k = k

    # Frequency in Hz = k / duration
    peak_freq = peak_k / duration
    return round(peak_freq, 1)

def test_results_json_exists_and_valid():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Missing results file at {results_path}"

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected_keys = {"optimal_dt", "dominant_frequency_hz", "sequence"}
    actual_keys = set(data.keys())

    assert expected_keys.issubset(actual_keys), \
        f"Missing keys in results.json. Expected {expected_keys}, found {actual_keys}"

def test_optimal_dt():
    results_path = "/home/user/results.json"
    with open(results_path, 'r') as f:
        data = json.load(f)

    assert data["optimal_dt"] == 0.02, \
        f"Incorrect optimal_dt. Expected 0.02, got {data.get('optimal_dt')}"

def test_sequence_extraction():
    results_path = "/home/user/results.json"
    with open(results_path, 'r') as f:
        data = json.load(f)

    assert data["sequence"] == "MKVLAEFY", \
        f"Incorrect sequence. Expected 'MKVLAEFY', got '{data.get('sequence')}'"

def test_dominant_frequency():
    results_path = "/home/user/results.json"
    with open(results_path, 'r') as f:
        data = json.load(f)

    expected_freq = get_expected_frequency()
    actual_freq = data.get("dominant_frequency_hz")

    assert actual_freq == expected_freq, \
        f"Incorrect dominant_frequency_hz. Expected {expected_freq}, got {actual_freq}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
