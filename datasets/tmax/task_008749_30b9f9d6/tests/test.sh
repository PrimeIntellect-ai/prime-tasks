#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import re
import pytest
import numpy as np
from scipy import stats
from scipy.optimize import minimize

RESULTS_PATH = "/home/user/results.json"
DATA_PATH = "/home/user/data.txt"
FOUR_DECIMAL_NUMBER = re.compile(r"-?(?:0|[1-9][0-9]*)\.[0-9]{4}")


def _parse_number(token):
    assert FOUR_DECIMAL_NUMBER.fullmatch(token), f"All numerical values must be written with exactly 4 decimal places; got {token!r}"
    return float(token)


def _reject_constant(token):
    pytest.fail(f"Invalid non-finite JSON number: {token}")


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(
                f,
                parse_float=_parse_number,
                parse_int=_parse_number,
                parse_constant=_reject_constant,
            )
        except json.JSONDecodeError:
            pytest.fail("/home/user/results.json is not a valid JSON file.")


def ks_objective(distribution, data, params):
    first, scale = float(params[0]), float(params[1])
    if not math.isfinite(first) or not math.isfinite(scale) or scale <= 0:
        return 1e6
    if distribution == "normal":
        value = stats.kstest(data, "norm", args=(first, scale)).statistic
    else:
        value = stats.kstest(data, "laplace", args=(first, scale)).statistic
    return float(value) if math.isfinite(value) else 1e6


def recompute_optimization(distribution, data):
    center = float(np.mean(data)) if distribution == "normal" else float(np.median(data))
    # Both common interpretations of sample standard deviation are accepted as
    # initializations; each optimization is independently recomputed here.
    solutions = []
    for ddof in (0, 1):
        initial = [center, float(np.std(data, ddof=ddof))]
        result = minimize(
            lambda p: ks_objective(distribution, data, p),
            initial,
            method="Nelder-Mead",
        )
        solutions.append((np.asarray(result.x, dtype=float), ks_objective(distribution, data, result.x)))
    return solutions


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), "The file /home/user/results.json does not exist."
    assert os.path.isfile(RESULTS_PATH), "/home/user/results.json is not a file."


def test_results_format_and_values():
    results = load_results()

    expected_keys = {
        "normal_params",
        "normal_ks_distance",
        "laplace_params",
        "laplace_ks_distance",
        "best_fit"
    }

    assert set(results.keys()) == expected_keys, f"JSON keys do not match the expected keys. Found: {list(results.keys())}"

    assert isinstance(results["normal_params"], list), "normal_params must be a list"
    assert len(results["normal_params"]) == 2, "normal_params must contain exactly two elements [mu, sigma]"
    assert isinstance(results["laplace_params"], list), "laplace_params must be a list"
    assert len(results["laplace_params"]) == 2, "laplace_params must contain exactly two elements [loc, scale]"

    assert isinstance(results["normal_ks_distance"], (int, float)), "normal_ks_distance must be a number"
    assert isinstance(results["laplace_ks_distance"], (int, float)), "laplace_ks_distance must be a number"

    assert results["best_fit"] in ["Normal", "Laplace"], "best_fit must be either 'Normal' or 'Laplace'"

    # The data was generated from a Laplace distribution, so Laplace should be the best fit
    assert results["best_fit"] == "Laplace", "The best fit should be 'Laplace'"
    assert results["laplace_ks_distance"] < results["normal_ks_distance"], "Laplace KS distance should be smaller than Normal KS distance"

    # The Laplace parameters should be close to the true parameters (loc=5.0, scale=2.0)
    loc, scale = results["laplace_params"]
    assert math.isclose(loc, 5.0, abs_tol=0.5), f"Expected Laplace loc to be near 5.0, got {loc}"
    assert math.isclose(scale, 2.0, abs_tol=0.5), f"Expected Laplace scale to be near 2.0, got {scale}"

    # The KS distances should be reasonable (between 0 and 1)
    assert 0 <= results["normal_ks_distance"] <= 1, "KS distance must be between 0 and 1"
    assert 0 <= results["laplace_ks_distance"] <= 1, "KS distance must be between 0 and 1"

    for key in ("normal_params", "laplace_params"):
        assert all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in results[key]), f"{key} must contain numbers"
        assert all(math.isfinite(v) for v in results[key]), f"{key} must contain finite numbers"
        assert results[key][1] > 0, f"The scale parameter in {key} must be positive"

    data = np.loadtxt(DATA_PATH, dtype=float)
    assert data.ndim == 1 and data.size == 500, "The source dataset must contain 500 values"

    normal_refs = recompute_optimization("normal", data)
    laplace_refs = recompute_optimization("laplace", data)

    submitted_normal_ks = ks_objective("normal", data, results["normal_params"])
    submitted_laplace_ks = ks_objective("laplace", data, results["laplace_params"])

    # Distances must be the KS statistics produced by the submitted parameters,
    # allowing only the effect of independently rounding parameters and distances.
    assert abs(results["normal_ks_distance"] - submitted_normal_ks) <= 1.1e-4, (
        f"normal_ks_distance does not match the KS statistic for normal_params: "
        f"reported {results['normal_ks_distance']}, recomputed {submitted_normal_ks}"
    )
    assert abs(results["laplace_ks_distance"] - submitted_laplace_ks) <= 1.1e-4, (
        f"laplace_ks_distance does not match the KS statistic for laplace_params: "
        f"reported {results['laplace_ks_distance']}, recomputed {submitted_laplace_ks}"
    )

    # Each submitted fit must attain the Nelder-Mead optimum recomputed from the
    # required initialization, rather than merely reporting a plausible distance.
    normal_ref_distances = [distance for _, distance in normal_refs]
    laplace_ref_distances = [distance for _, distance in laplace_refs]
    assert submitted_normal_ks <= max(normal_ref_distances) + 2e-4, (
        f"normal_params are not an optimized KS fit: got {submitted_normal_ks}, references {normal_ref_distances}"
    )
    assert submitted_laplace_ks <= max(laplace_ref_distances) + 2e-4, (
        f"laplace_params are not an optimized KS fit: got {submitted_laplace_ks}, references {laplace_ref_distances}"
    )
    assert min(abs(results["normal_ks_distance"] - d) for d in normal_ref_distances) <= 3e-4, (
        "normal_ks_distance does not match a recomputed Nelder-Mead optimum"
    )
    assert min(abs(results["laplace_ks_distance"] - d) for d in laplace_ref_distances) <= 3e-4, (
        "laplace_ks_distance does not match a recomputed Nelder-Mead optimum"
    )

    recomputed_best = "Normal" if submitted_normal_ks < submitted_laplace_ks else "Laplace"
    assert results["best_fit"] == recomputed_best, "best_fit does not identify the lower recomputed KS statistic"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
