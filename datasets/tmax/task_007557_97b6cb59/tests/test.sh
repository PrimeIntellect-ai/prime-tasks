#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import minimize
from scipy.special import logsumexp
from scipy.stats import wasserstein_distance

DATA_PATH = Path("/home/user/data.csv")
RESULTS_PATH = Path("/home/user/results.json")
PLOT_PATH = Path("/home/user/fit_plot.png")


@pytest.fixture(scope="session", autouse=True)
def run_fitting_script():
    """Find and execute the submitted Python fitting artifact."""
    original_data = DATA_PATH.read_bytes()
    candidates = []
    for path in Path("/home/user").rglob("*.py"):
        if "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        priority = int("results.json" in text and "fit_plot.png" in text)
        candidates.append((priority, path.stat().st_mtime, path, text))

    assert candidates, "No Python fitting script was found under /home/user"
    candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)

    errors = []
    succeeded = False
    for _, _, script, source in candidates:
        for output in (RESULTS_PATH, PLOT_PATH):
            try:
                output.unlink()
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["MPLBACKEND"] = "Agg"
        try:
            proc = subprocess.run(
                ["python3", str(script)],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=240,
            )
            if proc.returncode == 0 and RESULTS_PATH.is_file() and PLOT_PATH.is_file():
                assert "sklearn.mixture" not in source and "GaussianMixture" not in source, \
                    "The fitting script must not use sklearn.mixture.GaussianMixture"
                succeeded = True
                break
            errors.append(f"{script}: exit {proc.returncode}: {proc.stdout[-1000:]}")
        except subprocess.TimeoutExpired:
            errors.append(f"{script}: timed out")
        finally:
            DATA_PATH.write_bytes(original_data)

    assert succeeded, "No submitted Python script successfully generated both outputs. " + " | ".join(errors)


def load_results():
    with RESULTS_PATH.open("r") as f:
        return json.load(f)


def negative_log_likelihood(params, data):
    mu1, std1, mu2, std2, weight = params
    if std1 <= 0 or std2 <= 0 or not 0 < weight < 1:
        return np.inf
    logp1 = math.log(weight) - math.log(std1) - 0.5 * math.log(2 * math.pi) \
            - 0.5 * ((data - mu1) / std1) ** 2
    logp2 = math.log1p(-weight) - math.log(std2) - 0.5 * math.log(2 * math.pi) \
            - 0.5 * ((data - mu2) / std2) ** 2
    return float(-np.sum(logsumexp(np.vstack((logp1, logp2)), axis=0)))


def independently_fit(data):
    """Compute a data-derived reference optimum using several bounded starts."""
    lo, hi = float(np.min(data)), float(np.max(data))
    overall_std = float(np.std(data))
    bounds = [
        (lo, hi),
        (0.05, max(0.1, 2 * overall_std)),
        (lo, hi),
        (0.05, max(0.1, 2 * overall_std)),
        (0.01, 0.99),
    ]
    starts = []
    for q in (0.25, 0.35, 0.45, 0.55, 0.65):
        cut = np.quantile(data, q)
        left = data[data <= cut]
        right = data[data > cut]
        if len(left) < 2 or len(right) < 2:
            continue
        starts.append([
            float(np.mean(left)), max(0.05, float(np.std(left))),
            float(np.mean(right)), max(0.05, float(np.std(right))),
            len(left) / len(data),
        ])

    fits = [minimize(
        negative_log_likelihood,
        x0=np.asarray(start),
        args=(data,),
        method="L-BFGS-B",
        bounds=bounds,
        options={"maxiter": 3000, "ftol": 1e-12, "gtol": 1e-8},
    ) for start in starts]
    valid = [fit for fit in fits if np.isfinite(fit.fun)]
    assert valid, "Independent reference fit failed"
    return min(valid, key=lambda fit: fit.fun)


def test_fit_plot_exists():
    """Verify that the fit plot was generated."""
    plot_path = "/home/user/fit_plot.png"
    assert os.path.isfile(plot_path), f"Expected plot file not found at {plot_path}"


def test_fit_plot_is_valid_png():
    assert PLOT_PATH.stat().st_size > 1000, "fit_plot.png is empty or implausibly small"
    with PLOT_PATH.open("rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "fit_plot.png is not a PNG image"
    import matplotlib.image as mpimg
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "fit_plot.png is not a usable plot image"


def test_results_json_exists_and_schema():
    """Verify that results.json exists and contains the correct schema."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Expected results file not found at {results_path}"

    with open(results_path, "r") as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected_keys = {"mu1", "std1", "mu2", "std2", "weight", "wasserstein_distance"}
    assert set(res.keys()) == expected_keys, f"JSON keys do not match expected schema. Found: {list(res.keys())}"

    for key in expected_keys:
        assert isinstance(res[key], (int, float)), f"Value for {key} must be a float."
        assert not isinstance(res[key], bool) and math.isfinite(res[key]), f"Value for {key} must be finite numeric data."


def test_results_values():
    """Verify that the fitted parameters and Wasserstein distance are within expected ranges."""
    results_path = "/home/user/results.json"
    if not os.path.isfile(results_path):
        pytest.skip("results.json not found")

    with open(results_path, "r") as f:
        res = json.load(f)

    assert 1.7 <= res["mu1"] <= 2.3, f"mu1 value {res['mu1']} is out of bounds (expected ~2.0)"
    assert 7.2 <= res["mu2"] <= 7.8, f"mu2 value {res['mu2']} is out of bounds (expected ~7.5)"
    assert 0.6 <= res["std1"] <= 1.0, f"std1 value {res['std1']} is out of bounds (expected ~0.8)"
    assert 1.0 <= res["std2"] <= 1.4, f"std2 value {res['std2']} is out of bounds (expected ~1.2)"
    assert 0.25 <= res["weight"] <= 0.45, f"weight value {res['weight']} is out of bounds (expected ~0.35)"
    assert res["wasserstein_distance"] < 0.15, f"wasserstein_distance {res['wasserstein_distance']} is too high (expected < 0.15)"


def test_parameters_are_actual_mle():
    data = pd.read_csv(DATA_PATH)["value"].to_numpy(dtype=float)
    res = load_results()
    assert res["mu1"] < res["mu2"], "mu1 must identify the component with the smaller mean"
    assert res["std1"] > 0 and res["std2"] > 0
    assert 0 <= res["weight"] <= 1

    submitted = np.array([res["mu1"], res["std1"], res["mu2"], res["std2"], res["weight"]], dtype=float)
    submitted_nll = negative_log_likelihood(submitted, data)
    reference = independently_fit(data)
    assert submitted_nll <= reference.fun + 0.25, \
        f"Reported parameters are not an MLE-quality fit (NLL {submitted_nll:.6f}, reference {reference.fun:.6f})"


def test_wasserstein_distance_recomputed():
    data = pd.read_csv(DATA_PATH)["value"].to_numpy(dtype=float)
    res = load_results()
    distances = []
    for seed in (104729, 130363, 155921, 181081, 205019, 230003, 257053):
        rng = np.random.default_rng(seed)
        choose_first = rng.random(100000) < res["weight"]
        synthetic = np.empty(100000, dtype=float)
        n1 = int(np.sum(choose_first))
        synthetic[choose_first] = rng.normal(res["mu1"], res["std1"], n1)
        synthetic[~choose_first] = rng.normal(res["mu2"], res["std2"], 100000 - n1)
        distances.append(float(wasserstein_distance(data, synthetic)))

    reported = res["wasserstein_distance"]
    assert reported >= 0
    assert min(distances) - 0.025 <= reported <= max(distances) + 0.025, \
        f"Reported Wasserstein distance {reported} is inconsistent with recomputation {distances}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
