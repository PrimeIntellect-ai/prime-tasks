#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit

RESULTS_PATH = "/home/user/model_results.json"
DATA_PATH = "/home/user/reaction_rate.csv"


def exponential_model(t, L, k):
    return L * (1.0 - np.exp(-k * t))


def hyperbolic_model(t, vmax, km):
    return vmax * t / (km + t)


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} is not a valid JSON file.")


def compute_expected_results():
    data = pd.read_csv(DATA_PATH)
    assert list(data.columns) == ["time", "rate"], "Input dataset columns were modified."

    time = data["time"].to_numpy(dtype=float)
    rate = data["rate"].to_numpy(dtype=float)
    cumulative = np.zeros_like(rate, dtype=float)
    cumulative[1:] = np.cumsum(
        0.5 * (rate[:-1] + rate[1:]) * (time[1:] - time[:-1])
    )

    exp_params, _ = curve_fit(
        exponential_model, time, cumulative, p0=[10.0, 0.1]
    )
    hyp_params, _ = curve_fit(
        hyperbolic_model, time, cumulative, p0=[10.0, 1.0]
    )

    exp_residuals = cumulative - exponential_model(time, *exp_params)
    hyp_residuals = cumulative - hyperbolic_model(time, *hyp_params)
    n = len(time)
    aic_exp = n * np.log(np.sum(exp_residuals ** 2) / n) + 2 * 2
    aic_hyp = n * np.log(np.sum(hyp_residuals ** 2) / n) + 2 * 2

    if aic_exp < aic_hyp:
        best_name = "Exponential"
        best_model = exponential_model
        best_params = exp_params
        initial_guess = [10.0, 0.1]
    else:
        best_name = "Hyperbolic"
        best_model = hyperbolic_model
        best_params = hyp_params
        initial_guess = [10.0, 1.0]

    boot_param1 = []
    np.random.seed(42)
    for _ in range(1000):
        indices = np.random.choice(n, size=n, replace=True)
        try:
            fitted, _ = curve_fit(
                best_model,
                time[indices],
                cumulative[indices],
                p0=initial_guess,
            )
        except RuntimeError:
            continue
        boot_param1.append(float(fitted[0]))

    assert boot_param1, "Reference bootstrap produced no successful fits."
    ci_lower, ci_upper = np.percentile(boot_param1, [2.5, 97.5])

    return {
        "best_model": best_name,
        "aic_exponential": round(float(aic_exp), 2),
        "aic_hyperbolic": round(float(aic_hyp), 2),
        "param1_estimate": round(float(best_params[0]), 4),
        "param1_ci_lower": round(float(ci_lower), 4),
        "param1_ci_upper": round(float(ci_upper), 4),
    }


def test_input_dataset_is_original():
    np.random.seed(123)
    time = np.linspace(0, 10, 50)
    rate = 4.8 * np.exp(-0.4 * time)
    rate += np.random.normal(0, 0.15, size=len(time))
    expected_buffer = io.StringIO()
    pd.DataFrame({"time": time, "rate": rate}).to_csv(expected_buffer, index=False)

    assert os.path.isfile(DATA_PATH), f"File {DATA_PATH} is missing."
    with open(DATA_PATH, "r") as f:
        actual_text = f.read()
    assert actual_text == expected_buffer.getvalue(), "The provided input dataset was modified."


def test_model_results_exists():
    assert os.path.exists(RESULTS_PATH), f"File {RESULTS_PATH} is missing."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."


def test_model_results_content_and_invariants():
    results = load_results()

    expected_keys = {
        "best_model",
        "aic_exponential",
        "aic_hyperbolic",
        "param1_estimate",
        "param1_ci_lower",
        "param1_ci_upper",
    }

    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"Missing keys in JSON: {missing_keys}"

    extra_keys = set(results.keys()) - expected_keys
    assert not extra_keys, f"Unexpected extra keys in JSON: {extra_keys}"

    assert isinstance(results["best_model"], str), "best_model must be a string."
    numeric_keys = [
        "aic_exponential",
        "aic_hyperbolic",
        "param1_estimate",
        "param1_ci_lower",
        "param1_ci_upper",
    ]
    for key in numeric_keys:
        assert isinstance(results[key], (int, float)), f"{key} must be a number."
        assert math.isfinite(results[key]), f"{key} must be finite."

    assert results["best_model"] == "Exponential", "The Exponential model should be identified as the best_model."
    assert results["aic_exponential"] < results["aic_hyperbolic"], "AIC for Exponential should be lower than Hyperbolic."

    est = results["param1_estimate"]
    assert 10.0 < est < 14.0, f"param1_estimate ({est}) is far from the expected true value (~12.0)."

    ci_lower = results["param1_ci_lower"]
    ci_upper = results["param1_ci_upper"]
    assert ci_lower <= est, "Confidence interval lower bound must be <= the estimate."
    assert est <= ci_upper, "Confidence interval upper bound must be >= the estimate."
    assert ci_lower < ci_upper, "Confidence interval lower bound must be strictly less than the upper bound."
    assert ci_lower > 0, "Confidence interval lower bound should be positive for this physical process."


def test_results_match_required_analysis():
    results = load_results()
    expected = compute_expected_results()
    assert results == expected, f"Results do not match the required integration, fits, AIC, and bootstrap calculations. Expected {expected}, got {results}."
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
