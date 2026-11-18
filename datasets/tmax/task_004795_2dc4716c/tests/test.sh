#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import pytest
import numpy as np
import pandas as pd
from scipy.optimize import least_squares

RESULTS_PATH = "/home/user/fit_results.json"
DATA_PATH = "/home/user/ringdown_data.csv"
REQUIRED_KEYS = ["A", "alpha", "f", "phi", "m", "c"]


def load_results():
    try:
        with open(RESULTS_PATH, "r") as f:
            return json.load(f)
    except Exception as e:
        pytest.fail(f"Could not read or parse {RESULTS_PATH} as JSON: {e}")


def model(t, p):
    A, alpha, f, phi, m, c = p
    return A * np.exp(-alpha * t) * np.cos(2 * np.pi * f * t + phi) + m * t + c


def test_fit_results_json_exists():
    """Verify that the fit_results.json file exists."""
    assert os.path.exists(RESULTS_PATH), f"Missing file: {RESULTS_PATH}"
    assert os.path.isfile(RESULTS_PATH), f"Not a file: {RESULTS_PATH}"


def test_fit_results_values():
    """Verify that the fitted parameters are within the expected tolerances."""
    res = load_results()

    for key in REQUIRED_KEYS:
        assert key in res, f"Missing key '{key}' in {RESULTS_PATH}"
        assert isinstance(res[key], (int, float)), f"Value for '{key}' must be a number"

    assert set(res) == set(REQUIRED_KEYS), f"{RESULTS_PATH} must contain exactly the six required keys"
    for key in REQUIRED_KEYS:
        assert type(res[key]) in (int, float), f"Value for '{key}' must be a number, not a boolean"
        assert math.isfinite(res[key]), f"Value for '{key}' must be finite"

    # Original parameter assertions.
    assert abs(res['f'] - 15.3) < 0.2, f"Frequency 'f' ({res['f']}) is not within tolerance of 15.3"
    assert abs(abs(res['A']) - 4.5) < 0.3, f"Amplitude 'A' ({res['A']}) is not within tolerance of 4.5"
    assert abs(res['alpha'] - 0.8) < 0.1, f"Decay rate 'alpha' ({res['alpha']}) is not within tolerance of 0.8"
    assert abs(res['m'] - 1.2) < 0.1, f"Slope 'm' ({res['m']}) is not within tolerance of 1.2"
    assert abs(res['c'] - (-0.7)) < 0.2, f"Intercept 'c' ({res['c']}) is not within tolerance of -0.7"


def test_parameters_fit_supplied_data_and_spectrum():
    """Exercise all six submitted parameters against the supplied observations."""
    assert os.path.isfile(DATA_PATH), f"Missing data file: {DATA_PATH}"
    df = pd.read_csv(DATA_PATH)
    assert {'t', 'y'}.issubset(df.columns), "Dataset must contain t and y columns"
    t = df['t'].to_numpy(dtype=float)
    y = df['y'].to_numpy(dtype=float)
    assert len(t) > 10 and len(t) == len(y)
    assert np.all(np.isfinite(t)) and np.all(np.isfinite(y))

    res = load_results()
    submitted = np.array([res[k] for k in REQUIRED_KEYS], dtype=float)

    # Derive the dominant frequency from the actual data after removing linear drift.
    trend = np.polyfit(t, y, 1)
    detrended = y - np.polyval(trend, t)
    dt = float(np.median(np.diff(t)))
    frequencies = np.fft.rfftfreq(len(t), d=dt)
    spectrum = np.abs(np.fft.rfft(detrended - detrended.mean()))
    usable = frequencies > 0.5
    fft_frequency = float(frequencies[usable][np.argmax(spectrum[usable])])
    assert abs(res['f'] - fft_frequency) < 0.25, (
        f"Submitted frequency {res['f']} disagrees with the data's dominant spectral frequency {fft_frequency}"
    )

    # Obtain a data-derived reference fit initialized with that FFT frequency.
    slope0, intercept0 = trend
    amplitude0 = max(0.1, float(np.max(np.abs(detrended))))
    p0 = np.array([amplitude0, 0.5, fft_frequency, 0.0, slope0, intercept0])
    lower = np.array([1e-8, 1e-8, max(1e-8, fft_frequency - 1.0), -2*np.pi, -np.inf, -np.inf])
    upper = np.array([max(100.0, 10.0 * amplitude0), 10.0, fft_frequency + 1.0, 2*np.pi, np.inf, np.inf])
    reference = least_squares(
        lambda p: model(t, p) - y,
        p0,
        bounds=(lower, upper),
        x_scale='jac',
        max_nfev=10000,
    )
    reference_rmse = float(np.sqrt(np.mean((model(t, reference.x) - y) ** 2)))

    submitted_prediction = model(t, submitted)
    assert np.all(np.isfinite(submitted_prediction)), "Submitted parameters produce non-finite predictions"
    submitted_rmse = float(np.sqrt(np.mean((submitted_prediction - y) ** 2)))
    assert submitted_rmse <= reference_rmse + 0.08, (
        f"Submitted six-parameter model does not fit the data: RMSE {submitted_rmse:.6f}, "
        f"data-derived reference RMSE {reference_rmse:.6f}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
