#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import solve_ivp
from scipy.signal import butter, filtfilt

RESULT_PATH = '/home/user/analysis_results.json'
DATA_PATH = '/home/user/probe_signal.csv'


def load_results():
    assert os.path.exists(RESULT_PATH), f"The file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"The path {RESULT_PATH} is not a file."

    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULT_PATH} does not contain valid JSON.")


def compute_expected_results():
    assert os.path.isfile(DATA_PATH), f"The input file {DATA_PATH} does not exist."
    frame = pd.read_csv(DATA_PATH)
    assert list(frame.columns) == ['time', 'signal']

    time = frame['time'].to_numpy(dtype=float)
    signal = frame['signal'].to_numpy(dtype=float)

    b, a = butter(N=2, Wn=0.2)
    smoothed_signal = filtfilt(b, a, signal)

    P0 = 10.0
    r = 0.05
    K = 500.0

    solution_a = solve_ivp(
        lambda t, p: r * p,
        (time[0], time[-1]),
        [P0],
        method='RK45',
        t_eval=time,
        rtol=1e-6,
        atol=1e-9,
    ).y[0]

    solution_b = solve_ivp(
        lambda t, p: r * p * (1.0 - p / K),
        (time[0], time[-1]),
        [P0],
        method='RK45',
        t_eval=time,
        rtol=1e-6,
        atol=1e-9,
    ).y[0]

    analytical_b = K / (1.0 + ((K - P0) / P0) * np.exp(-r * time))
    max_diff = float(np.max(np.abs(solution_b - analytical_b)))
    sse_a = float(np.sum((smoothed_signal - solution_a) ** 2))
    sse_b = float(np.sum((smoothed_signal - solution_b) ** 2))
    n = len(time)
    aic_a = float(n * np.log(sse_a / n) + 2 * 1)
    aic_b = float(n * np.log(sse_b / n) + 2 * 2)

    return {
        'max_diff': round(max_diff, 4),
        'sse_A': round(sse_a, 4),
        'sse_B': round(sse_b, 4),
        'aic_A': round(aic_a, 4),
        'aic_B': round(aic_b, 4),
        'best_model': 'A' if aic_a < aic_b else 'B',
    }


def test_analysis_results_exists_and_valid():
    data = load_results()

    expected_keys = {'max_diff', 'sse_A', 'sse_B', 'aic_A', 'aic_B', 'best_model'}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, but got {set(data.keys())}."

    assert isinstance(data['max_diff'], (int, float)), 'max_diff must be a float'
    assert isinstance(data['sse_A'], (int, float)), 'sse_A must be a float'
    assert isinstance(data['sse_B'], (int, float)), 'sse_B must be a float'
    assert isinstance(data['aic_A'], (int, float)), 'aic_A must be a float'
    assert isinstance(data['aic_B'], (int, float)), 'aic_B must be a float'
    assert isinstance(data['best_model'], str), 'best_model must be a string'

    for key in ('max_diff', 'sse_A', 'sse_B', 'aic_A', 'aic_B'):
        assert math.isfinite(data[key]), f'{key} must be finite'


def test_analysis_results_logic():
    data = load_results()

    # The RK45 numerical solution should be very close to the analytical solution
    assert 0.0 <= data['max_diff'] < 1.0, f"max_diff is {data['max_diff']}, which is unusually large for RK45 vs Analytical."

    # Model B (Logistic) should fit the data much better than Model A (Exponential)
    assert data['sse_B'] < data['sse_A'], 'SSE for Model B should be less than SSE for Model A.'

    # AIC for Model B should be lower
    assert data['aic_B'] < data['aic_A'], 'AIC for Model B should be less than AIC for Model A.'

    # Best model should be B
    assert data['best_model'] == 'B', f"Expected best_model to be 'B', got '{data['best_model']}'."

    # Check that AIC values are consistent with SSE values
    n = 101
    expected_aic_A = n * math.log(data['sse_A'] / n) + 2 * 1
    expected_aic_B = n * math.log(data['sse_B'] / n) + 2 * 2

    assert abs(data['aic_A'] - expected_aic_A) < 0.1, f"aic_A is inconsistent with sse_A. Expected approx {expected_aic_A}, got {data['aic_A']}"
    assert abs(data['aic_B'] - expected_aic_B) < 0.1, f"aic_B is inconsistent with sse_B. Expected approx {expected_aic_B}, got {data['aic_B']}"


def test_results_match_input_analysis():
    data = load_results()
    expected = compute_expected_results()

    for key in ('max_diff', 'sse_A', 'sse_B', 'aic_A', 'aic_B'):
        assert data[key] == pytest.approx(expected[key], abs=1e-7), \
            f"{key} is incorrect for {DATA_PATH}: expected {expected[key]}, got {data[key]}"

    assert data['best_model'] == expected['best_model'], \
        f"best_model is incorrect: expected {expected['best_model']}, got {data['best_model']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
