#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import warnings

import numpy as np
import pytest
from scipy.integrate import quad
from scipy.special import logsumexp
from scipy.stats import norm
from sklearn.mixture import GaussianMixture

RESULTS_PATH = "/home/user/results.json"
DATA_PATH = "/home/user/sensor_data.csv"
EXPECTED_KEYS = {
    "gmm_weights", "gmm_means", "gmm_variances",
    "integral_value", "naive_log_likelihoods", "stable_log_likelihoods"
}


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON.")


def compute_expected():
    data = np.loadtxt(DATA_PATH, delimiter=",").reshape(-1, 1)
    gmm = GaussianMixture(n_components=2, random_state=42, max_iter=1000)
    gmm.fit(data)

    order = np.argsort(gmm.weights_)
    weights = gmm.weights_[order]
    means = gmm.means_.reshape(-1)[order]
    variances = gmm.covariances_.reshape(-1)[order]

    def mixture_pdf(x):
        return float(sum(
            weights[i] * norm.pdf(x, loc=means[i], scale=np.sqrt(variances[i]))
            for i in range(2)
        ))

    integral_value = quad(mixture_pdf, -1000, 1000)[0]
    extremes = [50.0, 100.0, 500.0, 1000.0]

    naive = []
    stable = []
    for x in extremes:
        density = sum(
            weights[i] * norm.pdf(x, loc=means[i], scale=np.sqrt(variances[i]))
            for i in range(2)
        )
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            naive_value = np.log(density)
        naive.append("-inf" if np.isneginf(naive_value) else round(float(naive_value), 6))

        terms = [
            np.log(weights[i]) + norm.logpdf(x, loc=means[i], scale=np.sqrt(variances[i]))
            for i in range(2)
        ]
        stable.append(round(float(logsumexp(terms)), 6))

    return {
        "gmm_weights": [round(float(x), 6) for x in weights],
        "gmm_means": [round(float(x), 6) for x in means],
        "gmm_variances": [round(float(x), 6) for x in variances],
        "integral_value": round(float(integral_value), 6),
        "naive_log_likelihoods": naive,
        "stable_log_likelihoods": stable,
    }


EXPECTED = compute_expected()


def test_results_file_exists():
    """Test that the results.json file exists."""
    assert os.path.exists(RESULTS_PATH), f"{RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."


def test_results_json_structure():
    """Test that the JSON file has the exact expected keys."""
    res = load_results()
    assert set(res.keys()) == EXPECTED_KEYS, f"JSON keys do not match expected. Found: {list(res.keys())}"


def test_gmm_parameters():
    """Test the extracted GMM parameters for correctness and sorting."""
    res = load_results()
    weights = res["gmm_weights"]
    means = res["gmm_means"]
    variances = res["gmm_variances"]

    assert len(weights) == 2, "gmm_weights must have exactly 2 elements."
    assert len(means) == 2, "gmm_means must have exactly 2 elements."
    assert len(variances) == 2, "gmm_variances must have exactly 2 elements."

    assert all(isinstance(x, float) for x in weights), "gmm_weights must be floats."
    assert all(isinstance(x, float) for x in means), "gmm_means must be floats."
    assert all(isinstance(x, float) for x in variances), "gmm_variances must be floats."

    assert weights[0] <= weights[1], "gmm_weights must be sorted in ascending order."
    assert abs(sum(weights) - 1.0) < 1e-2, "gmm_weights should sum to approximately 1.0."


def test_integral_value():
    """Test that the integral of the PDF is approximately 1.0."""
    res = load_results()
    integral = res["integral_value"]
    assert isinstance(integral, float), "integral_value must be a float."
    assert abs(integral - 1.0) < 1e-4, f"integral_value should be close to 1.0, got {integral}"


def test_naive_log_likelihoods():
    """Test that naive log likelihoods underflow to '-inf' for extreme values."""
    res = load_results()
    naive = res["naive_log_likelihoods"]
    assert len(naive) == 4, "naive_log_likelihoods must have exactly 4 elements."
    assert naive[-1] == "-inf", "The most extreme outlier (1000.0) should underflow to '-inf' in the naive method."


def test_stable_log_likelihoods():
    """Test that stable log likelihoods are finite negative floats."""
    res = load_results()
    stable = res["stable_log_likelihoods"]
    assert len(stable) == 4, "stable_log_likelihoods must have exactly 4 elements."
    assert all(isinstance(x, float) for x in stable), "All elements in stable_log_likelihoods must be floats."
    assert all(x < 0 for x in stable), "All log likelihoods should be negative."
    assert stable[-1] < -10000, f"Expected last stable log likelihood to be < -10000 (no underflow to -inf), got {stable[-1]}"


def test_values_match_fitted_model_and_six_decimal_rounding():
    """Recompute the required model, integral, and likelihoods from the supplied data."""
    res = load_results()
    for key in EXPECTED_KEYS:
        assert res[key] == EXPECTED[key], (
            f"{key} does not match the value obtained from the required GMM and "
            f"six-decimal rounding. Expected {EXPECTED[key]!r}, got {res[key]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
