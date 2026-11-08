#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from decimal import Decimal

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit

REPORT_PATH = "/home/user/analysis_report.json"
DATA_PATH = "/home/user/signal_data.csv"
REQUIRED_KEYS = ["T_peak", "optimized_mu", "optimized_a", "posterior_mean_c"]


def gaussian(t, a, c, mu, b):
    return a * np.exp(-c * (t - mu) ** 2) + b


def compute_expected_metrics():
    assert os.path.isfile(DATA_PATH), f"The signal data is missing: {DATA_PATH}"
    df = pd.read_csv(DATA_PATH)
    assert list(df.columns) == ["time", "current"], "Signal data must contain time and current columns."

    time = df["time"].to_numpy(dtype=float)
    current = df["current"].to_numpy(dtype=float)
    assert len(time) == 2000 and len(current) == 2000, "The supplied signal data was altered."
    assert np.all(np.isfinite(time)) and np.all(np.isfinite(current)), "Signal data contains non-finite values."

    # Verify that calculations are performed against the original task input.
    expected_time = np.linspace(0, 100, 2000)
    rng = np.random.RandomState(123)
    expected_current = (
        15.0 * np.exp(-0.5 * (expected_time - 45.0) ** 2)
        + 5.0
        + 3.0 * np.sin(2 * np.pi * 2.0 * expected_time)
        + 2.0 * np.cos(2 * np.pi * 3.5 * expected_time)
        + rng.normal(0, 0.5, size=len(expected_time))
    )
    assert np.allclose(time, expected_time, rtol=0, atol=1e-12), "The supplied signal times were altered."
    assert np.allclose(current, expected_current, rtol=0, atol=1e-12), "The supplied signal currents were altered."

    dt = float(np.mean(np.diff(time)))
    frequencies = np.fft.fftfreq(len(current), d=dt)
    spectrum = np.fft.fft(current)
    spectrum[np.abs(frequencies) >= 1.0] = 0
    filtered = np.fft.ifft(spectrum).real

    t_peak = float(time[np.argmax(filtered)])
    mask = (time >= t_peak - 5.0) & (time <= t_peak + 5.0)
    window_time = time[mask]
    window_current = filtered[mask]

    initial = [
        float(np.max(window_current) - np.min(window_current)),
        0.5,
        t_peak,
        float(np.median(window_current)),
    ]
    optimized, _ = curve_fit(
        gaussian,
        window_time,
        window_current,
        p0=initial,
        maxfev=100000,
    )
    optimized_a, optimized_c, optimized_mu, optimized_b = map(float, optimized)

    def log_posterior(c):
        if c < 0.01 or c > 2.0:
            return -np.inf
        prediction = gaussian(window_time, optimized_a, c, optimized_mu, optimized_b)
        residual = window_current - prediction
        return float(-0.5 * np.sum((residual / 0.2) ** 2))

    np.random.seed(42)
    current_c = optimized_c
    current_log_posterior = log_posterior(current_c)
    samples = np.empty(10000, dtype=float)
    for i in range(10000):
        proposed_c = float(np.random.normal(current_c, 0.05))
        proposed_log_posterior = log_posterior(proposed_c)
        if np.log(np.random.random()) < proposed_log_posterior - current_log_posterior:
            current_c = proposed_c
            current_log_posterior = proposed_log_posterior
        samples[i] = current_c

    posterior_mean_c = float(np.mean(samples[2000:]))
    return {
        "T_peak": round(t_peak, 3),
        "optimized_mu": round(optimized_mu, 3),
        "optimized_a": round(optimized_a, 3),
        "posterior_mean_c": round(posterior_mean_c, 3),
    }


def test_analysis_report_exists():
    """Test that the analysis report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"The analysis report is missing: {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"The path exists but is not a file: {REPORT_PATH}"


def test_analysis_report_content():
    """Validate the report against independently recomputed signal-analysis results."""
    try:
        with open(REPORT_PATH, "r") as f:
            raw = f.read()
        res = json.loads(raw)
        decimal_res = json.loads(raw, parse_float=Decimal, parse_int=Decimal)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    required_keys = ["T_peak", "optimized_mu", "optimized_a", "posterior_mean_c"]
    for key in required_keys:
        assert key in res, f"The JSON file is missing the required key: '{key}'"
        assert isinstance(res[key], (int, float)), f"The value for '{key}' must be a number."

    # Retain the original sanity assertions.
    assert 44.8 <= res["T_peak"] <= 45.2, f"T_peak is out of bounds: {res['T_peak']}"
    assert 44.9 <= res["optimized_mu"] <= 45.1, f"optimized_mu is out of bounds: {res['optimized_mu']}"
    assert 14.5 <= res["optimized_a"] <= 15.5, f"optimized_a is out of bounds: {res['optimized_a']}"
    assert 0.45 <= res["posterior_mean_c"] <= 0.55, f"posterior_mean_c is out of bounds: {res['posterior_mean_c']}"

    assert set(res) == set(REQUIRED_KEYS), "The JSON must contain exactly the four required keys."
    for key in REQUIRED_KEYS:
        assert not isinstance(res[key], bool), f"The value for '{key}' must be a numeric float."
        assert np.isfinite(float(res[key])), f"The value for '{key}' must be finite."
        value_as_decimal = decimal_res[key]
        assert isinstance(value_as_decimal, Decimal), f"The value for '{key}' must be numeric."
        assert value_as_decimal.as_tuple().exponent >= -3, f"The value for '{key}' was not rounded to 3 decimal places."

    expected = compute_expected_metrics()
    for key in REQUIRED_KEYS:
        assert abs(float(res[key]) - expected[key]) < 1e-12, (
            f"Incorrect {key}: got {res[key]}, expected {expected[key]} after rounding to 3 decimals."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
