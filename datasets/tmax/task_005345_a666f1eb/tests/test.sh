#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import math
import time
import numpy as np
import pytest
from scipy import stats

CLEANED_PATH = "/home/user/cleaned_embeddings.npy"
DIRTY_PATH = "/home/user/dirty_embeddings.npy"
REPORT_PATH = "/home/user/report.json"


def compute_expected_cleaned():
    dirty = np.load(DIRTY_PATH, allow_pickle=False)
    assert dirty.shape == (2000, 32), "dirty_embeddings.npy has an unexpected shape"

    storage = np.empty_like(dirty, dtype=np.float32)
    norms = np.empty(dirty.shape[0], dtype=np.float64)
    count = 0

    for vector in dirty:
        vector64 = vector.astype(np.float64, copy=False)
        vector_norm = np.linalg.norm(vector64)
        keep = True
        if count:
            similarities = (storage[:count].astype(np.float64) @ vector64) / (norms[:count] * vector_norm)
            if np.max(similarities) >= 0.92:
                keep = False
        if keep:
            storage[count] = vector
            norms[count] = vector_norm
            count += 1

    return storage[:count].copy()


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Required file is missing: {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file")


def test_cleaned_embeddings_exists_and_is_correct():
    assert os.path.isfile(CLEANED_PATH), f"Required file is missing: {CLEANED_PATH}"
    assert os.path.getsize(CLEANED_PATH) > 0, f"File {CLEANED_PATH} is empty"

    actual = np.load(CLEANED_PATH, allow_pickle=False)
    expected = compute_expected_cleaned()
    assert actual.dtype == np.float32, "cleaned_embeddings.npy must have dtype float32"
    assert actual.shape == expected.shape, (
        f"cleaned_embeddings.npy has shape {actual.shape}, expected {expected.shape}"
    )
    assert np.array_equal(actual, expected), (
        "cleaned_embeddings.npy is not the required sequential cosine-similarity cleaning result"
    )


def test_report_json_structure_and_values():
    report = load_report()
    expected_keys = {
        "cleaned_count",
        "mean_latency_alpha",
        "mean_latency_beta",
        "t_statistic",
        "p_value",
        "ci_95_lower",
        "ci_95_upper"
    }

    missing_keys = expected_keys - set(report.keys())
    extra_keys = set(report.keys()) - expected_keys
    assert not missing_keys, f"report.json is missing keys: {missing_keys}"
    assert not extra_keys, f"report.json has unexpected extra keys: {extra_keys}"

    assert isinstance(report["cleaned_count"], int), "cleaned_count must be an integer"
    assert report["cleaned_count"] > 0, "cleaned_count must be greater than 0"

    float_keys = [
        "mean_latency_alpha", "mean_latency_beta", "t_statistic",
        "p_value", "ci_95_lower", "ci_95_upper"
    ]
    for key in float_keys:
        assert isinstance(report[key], (int, float)), f"{key} must be a float"
        assert math.isfinite(report[key]), f"{key} must be finite"
        assert abs(float(report[key]) - round(float(report[key]), 4)) < 1e-10, (
            f"{key} must be rounded to 4 decimal places"
        )

    cleaned = np.load(CLEANED_PATH, allow_pickle=False)
    assert report["cleaned_count"] == len(cleaned), (
        "cleaned_count does not match cleaned_embeddings.npy"
    )

    mean_alpha = report["mean_latency_alpha"]
    mean_beta = report["mean_latency_beta"]
    assert 0.001 < mean_alpha < 0.1, f"mean_latency_alpha ({mean_alpha}) is outside realistic bounds"
    assert 0.001 < mean_beta < 0.1, f"mean_latency_beta ({mean_beta}) is outside realistic bounds"

    t_stat = report["t_statistic"]
    if mean_alpha > mean_beta:
        assert t_stat > 0, "t_statistic should be positive if mean_alpha > mean_beta"
    elif mean_alpha < mean_beta:
        assert t_stat < 0, "t_statistic should be negative if mean_alpha < mean_beta"

    p_val = report["p_value"]
    assert 0.0 <= p_val <= 1.0, f"p_value ({p_val}) must be between 0 and 1"

    ci_lower = report["ci_95_lower"]
    ci_upper = report["ci_95_upper"]
    assert ci_lower <= ci_upper, f"ci_95_lower ({ci_lower}) must be less than or equal to ci_95_upper ({ci_upper})"

    # Check that the reported Welch statistics are mutually consistent. With two
    # samples of size 100, Welch's degrees of freedom must lie in [99, 198].
    difference = float(mean_alpha) - float(mean_beta)
    midpoint = (float(ci_lower) + float(ci_upper)) / 2.0
    assert abs(midpoint - difference) <= 0.0002, (
        "The confidence interval is not centered on Mean Alpha - Mean Beta"
    )
    assert t_stat != 0, "The reported t-statistic cannot be zero for these measured means"

    standard_error = abs(difference / float(t_stat))
    half_width = (float(ci_upper) - float(ci_lower)) / 2.0
    critical_low = stats.t.ppf(0.975, 198)
    critical_high = stats.t.ppf(0.975, 99)
    assert critical_low * standard_error - 0.0002 <= half_width <= critical_high * standard_error + 0.0002, (
        "The confidence interval is inconsistent with the reported means and t-statistic"
    )

    possible_p_99 = 2.0 * stats.t.sf(abs(float(t_stat)), 99)
    possible_p_198 = 2.0 * stats.t.sf(abs(float(t_stat)), 198)
    p_min = min(possible_p_99, possible_p_198)
    p_max = max(possible_p_99, possible_p_198)
    assert p_min - 0.00011 <= float(p_val) <= p_max + 0.00011, (
        "p_value is inconsistent with the reported Welch t-statistic"
    )

    # Independently execute both supplied APIs on the prescribed deterministic
    # sample and compare the submitted benchmark with this fresh measurement.
    sys.path.insert(0, "/home/user")
    from inference_api import infer_model_alpha, infer_model_beta

    np.random.seed(42)
    indices = np.random.choice(len(cleaned), size=100, replace=False)
    sample = cleaned[indices]

    alpha_latencies = []
    for vector in sample:
        start = time.perf_counter()
        infer_model_alpha(vector)
        alpha_latencies.append(time.perf_counter() - start)

    beta_latencies = []
    for vector in sample:
        start = time.perf_counter()
        infer_model_beta(vector)
        beta_latencies.append(time.perf_counter() - start)

    alpha_latencies = np.asarray(alpha_latencies, dtype=np.float64)
    beta_latencies = np.asarray(beta_latencies, dtype=np.float64)
    fresh_alpha = float(np.mean(alpha_latencies))
    fresh_beta = float(np.mean(beta_latencies))
    fresh_t, fresh_p = stats.ttest_ind(alpha_latencies, beta_latencies, equal_var=False)

    var_alpha = np.var(alpha_latencies, ddof=1)
    var_beta = np.var(beta_latencies, ddof=1)
    se = math.sqrt(var_alpha / 100.0 + var_beta / 100.0)
    df = (var_alpha / 100.0 + var_beta / 100.0) ** 2 / (
        (var_alpha / 100.0) ** 2 / 99.0 + (var_beta / 100.0) ** 2 / 99.0
    )
    margin = stats.t.ppf(0.975, df) * se
    fresh_difference = fresh_alpha - fresh_beta
    fresh_lower = fresh_difference - margin
    fresh_upper = fresh_difference + margin

    assert abs(float(mean_alpha) - fresh_alpha) <= 0.0015, (
        "mean_latency_alpha does not agree with an independent execution of Model Alpha"
    )
    assert abs(float(mean_beta) - fresh_beta) <= 0.0015, (
        "mean_latency_beta does not agree with an independent execution of Model Beta"
    )
    assert abs(float(t_stat) - float(fresh_t)) <= 2.5, (
        "t_statistic does not agree with an independent benchmark"
    )
    assert abs(float(p_val) - float(fresh_p)) <= 0.03, (
        "p_value does not agree with an independent benchmark"
    )
    assert abs(float(ci_lower) - fresh_lower) <= 0.0015, (
        "ci_95_lower does not agree with an independent benchmark"
    )
    assert abs(float(ci_upper) - fresh_upper) <= 0.0015, (
        "ci_95_upper does not agree with an independent benchmark"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
