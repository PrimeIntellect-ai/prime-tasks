#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import runpy

import numpy as np
import pandas as pd
import pytest
import scipy.integrate

SCRIPT = "/home/user/fit_phonon.py"
OUTPUT = "/home/user/best_params.json"
DATA = "/home/user/spectroscopy_data.csv"


def _array_key(value):
    array = np.ascontiguousarray(np.asarray(value))
    return (array.dtype.str, array.shape, array.tobytes())


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_fit():
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} does not exist."
    assert os.path.isfile(DATA), f"Expected data file {DATA} does not exist."

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    data = pd.read_csv(DATA)
    t_exp = data["time"].to_numpy()
    sig_exp = data["signal"].to_numpy()

    original_solve_ivp = scipy.integrate.solve_ivp
    original_seed = np.random.seed
    original_uniform = np.random.uniform
    original_rfft = np.fft.rfft

    events = []
    seed_values = []
    gamma_draws = []
    omega_draws = []
    solved_candidates = []
    rfft_inputs = collections.Counter()

    def tracked_seed(value=None):
        events.append(("seed", value))
        seed_values.append(value)
        return original_seed(value)

    def tracked_uniform(low=0.0, high=1.0, size=None):
        events.append(("uniform", low, high))
        result = original_uniform(low, high, size)
        values = np.asarray(result).reshape(-1).astype(float).tolist()
        if float(low) == 0.1 and float(high) == 2.0:
            gamma_draws.extend(values)
        elif float(low) == 5.0 and float(high) == 10.0:
            omega_draws.extend(values)
        return result

    def tracked_rfft(a, *args, **kwargs):
        rfft_inputs[_array_key(a)] += 1
        return original_rfft(a, *args, **kwargs)

    def tracked_solve_ivp(fun, t_span, y0, *args, **kwargs):
        ode_args = kwargs.get("args") or ()
        deriv_x = np.asarray(fun(float(t_span[0]), np.array([1.0, 0.0]), *ode_args), dtype=float)
        deriv_v = np.asarray(fun(float(t_span[0]), np.array([0.0, 1.0]), *ode_args), dtype=float)
        assert deriv_x.shape == (2,) and deriv_v.shape == (2,), "The solve_ivp ODE must represent [x, dx/dt]."

        omega_sq = -float(deriv_x[1])
        gamma = -float(deriv_v[1]) / 2.0
        assert omega_sq > 0, "The oscillator passed to solve_ivp has an invalid omega term."
        omega = math.sqrt(omega_sq)

        t_eval = kwargs.get("t_eval")
        assert t_eval is not None, "solve_ivp must evaluate at the experimental time points using t_eval."
        assert np.array_equal(np.asarray(t_eval), t_exp), "solve_ivp t_eval must exactly match the CSV time points."
        assert np.allclose(np.asarray(y0, dtype=float), [1.0, 0.0]), "Incorrect oscillator initial conditions."

        result = original_solve_ivp(fun, t_span, y0, *args, **kwargs)
        assert result.success, f"solve_ivp failed for gamma={gamma}, omega={omega}: {result.message}"
        assert result.y.shape[1] == len(t_exp), "solve_ivp did not return every requested time point."
        solved_candidates.append((gamma, omega, np.asarray(result.y[0], dtype=float).copy()))
        events.append(("solve", gamma, omega))
        return result

    np.random.seed = tracked_seed
    np.random.uniform = tracked_uniform
    np.fft.rfft = tracked_rfft
    scipy.integrate.solve_ivp = tracked_solve_ivp
    try:
        runpy.run_path(SCRIPT, run_name="__main__")
    finally:
        scipy.integrate.solve_ivp = original_solve_ivp
        np.random.seed = original_seed
        np.random.uniform = original_uniform
        np.fft.rfft = original_rfft

    assert seed_values == [42], "The script must call np.random.seed(42) once immediately before sampling."
    assert events and events[0] == ("seed", 42), "np.random.seed(42) must precede the Monte Carlo sampling loop."
    assert len(gamma_draws) == 2000, f"Expected exactly 2000 gamma draws, observed {len(gamma_draws)}."
    assert len(omega_draws) == 2000, f"Expected exactly 2000 omega draws, observed {len(omega_draws)}."
    assert len(solved_candidates) == 2000, f"Expected solve_ivp to evaluate 2000 candidates, observed {len(solved_candidates)}."

    for index, (gamma, omega, _) in enumerate(solved_candidates):
        assert math.isclose(gamma, gamma_draws[index], rel_tol=0.0, abs_tol=1e-10), \
            f"solve_ivp candidate {index} did not use the corresponding sampled gamma."
        assert math.isclose(omega, omega_draws[index], rel_tol=0.0, abs_tol=1e-10), \
            f"solve_ivp candidate {index} did not use the corresponding sampled omega."

    assert all(0.1 <= value <= 2.0 for value in gamma_draws), "A sampled gamma is outside [0.1, 2.0]."
    assert all(5.0 <= value <= 10.0 for value in omega_draws), "A sampled omega is outside [5.0, 10.0]."

    for _, _, signal in solved_candidates:
        assert rfft_inputs[_array_key(signal)] > 0, "Every simulated solve_ivp signal must be passed to np.fft.rfft."
    assert rfft_inputs[_array_key(sig_exp)] > 0, "The experimental signal must be passed to np.fft.rfft."

    assert os.path.isfile(OUTPUT), "Running fit_phonon.py did not create best_params.json."
    with open(OUTPUT, "r") as handle:
        produced = json.load(handle)

    exp_magnitude = np.abs(original_rfft(sig_exp))
    costs = [
        np.sum((np.abs(original_rfft(signal)) - exp_magnitude) ** 2)
        for _, _, signal in solved_candidates
    ]
    best_index = int(np.argmin(costs))
    expected_gamma, expected_omega, _ = solved_candidates[best_index]
    assert math.isclose(float(produced["gamma"]), expected_gamma, rel_tol=0.0, abs_tol=1e-10), \
        "Saved gamma is not the minimum-cost sampled candidate under the required FFT-magnitude SSD."
    assert math.isclose(float(produced["omega"]), expected_omega, rel_tol=0.0, abs_tol=1e-10), \
        "Saved omega is not the minimum-cost sampled candidate under the required FFT-magnitude SSD."


def test_best_params_exists():
    """Test that the best_params.json file was created."""
    file_path = "/home/user/best_params.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."


def test_best_params_format_and_values():
    """Test that the JSON file has the correct format and contains the expected optimal parameters."""
    file_path = "/home/user/best_params.json"
    with open(file_path, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} is not valid JSON."

    assert "gamma" in params, "Key 'gamma' is missing from best_params.json."
    assert "omega" in params, "Key 'omega' is missing from best_params.json."

    gamma = params["gamma"]
    omega = params["omega"]

    assert isinstance(gamma, (int, float)), f"Expected 'gamma' to be a float, got {type(gamma).__name__}."
    assert isinstance(omega, (int, float)), f"Expected 'omega' to be a float, got {type(omega).__name__}."

    expected_gamma = 0.8118
    expected_omega = 7.4813

    assert math.isclose(gamma, expected_gamma, abs_tol=0.05), \
        f"Expected gamma to be near {expected_gamma}, but got {gamma}. Check your random seed, sampling bounds, and cost function."
    assert math.isclose(omega, expected_omega, abs_tol=0.05), \
        f"Expected omega to be near {expected_omega}, but got {omega}. Check your random seed, sampling bounds, and cost function."
TEST_EOF

if timeout 240s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
