#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy import stats
from sklearn.decomposition import PCA
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold, cross_val_score
from sklearn.preprocessing import StandardScaler

SCRIPT_PATH = "/home/user/run_pipeline.py"
RESULTS_PATH = "/home/user/results.json"
FEATURES_PATH = "/home/user/data/sensor_features.csv"
TARGETS_PATH = "/home/user/data/sensor_targets.csv"
EXPECTED_KEYS = {
    "n_components",
    "best_alpha",
    "baseline_mean_mse",
    "pca_mean_mse",
    "p_value",
    "ci_lower",
    "ci_upper",
}


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_twice():
    """Execute the submitted artifact and verify byte-for-byte reproducibility."""
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} must be a regular file."

    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=180,
    )
    assert os.path.isfile(RESULTS_PATH), f"Running {SCRIPT_PATH} did not create {RESULTS_PATH}."
    with open(RESULTS_PATH, "rb") as f:
        first_output = f.read()

    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=180,
    )
    assert os.path.isfile(RESULTS_PATH), f"Running {SCRIPT_PATH} a second time did not create {RESULTS_PATH}."
    with open(RESULTS_PATH, "rb") as f:
        second_output = f.read()

    assert first_output == second_output, "Repeated pipeline runs must produce exactly the same results.json."


def load_results():
    with open(RESULTS_PATH, "r") as f:
        return json.load(f)


def compute_expected_results():
    features = pd.read_csv(FEATURES_PATH)
    targets = pd.read_csv(TARGETS_PATH)
    merged = features.merge(targets, on="sample_id", how="inner").sort_values("sample_id").reset_index(drop=True)

    sensor_columns = [f"sensor_{i}" for i in range(20)]
    X_df = merged[sensor_columns].copy()
    X_df = X_df.fillna(X_df.mean())
    y = merged["target"].to_numpy()

    X_scaled = StandardScaler().fit_transform(X_df)
    full_pca = PCA().fit(X_scaled)
    cumulative_variance = np.cumsum(full_pca.explained_variance_ratio_)
    above_threshold = np.flatnonzero(cumulative_variance > 0.90)
    assert above_threshold.size > 0
    n_components = int(above_threshold[0] + 1)
    X_pca = PCA(n_components=n_components).fit_transform(X_scaled)

    baseline_cv = KFold(n_splits=5, shuffle=True, random_state=42)
    baseline_mses = -cross_val_score(
        Ridge(alpha=1.0),
        X_scaled,
        y,
        scoring="neg_mean_squared_error",
        cv=baseline_cv,
    )

    grid_cv = KFold(n_splits=5, shuffle=True, random_state=42)
    search = GridSearchCV(
        Ridge(),
        {"alpha": [0.1, 1.0, 10.0, 100.0]},
        scoring="neg_mean_squared_error",
        cv=grid_cv,
    )
    search.fit(X_pca, y)
    best_alpha = float(search.best_params_["alpha"])

    pca_cv = KFold(n_splits=5, shuffle=True, random_state=42)
    pca_mses = -cross_val_score(
        Ridge(alpha=best_alpha),
        X_pca,
        y,
        scoring="neg_mean_squared_error",
        cv=pca_cv,
    )

    p_value = float(stats.ttest_rel(baseline_mses, pca_mses).pvalue)
    differences = baseline_mses - pca_mses
    mean_difference = float(np.mean(differences))
    margin = float(stats.t.ppf(0.975, df=4) * stats.sem(differences))

    return {
        "n_components": n_components,
        "best_alpha": best_alpha,
        "baseline_mean_mse": float(np.mean(baseline_mses)),
        "pca_mean_mse": float(np.mean(pca_mses)),
        "p_value": p_value,
        "ci_lower": mean_difference - margin,
        "ci_upper": mean_difference + margin,
    }


def test_results_file_exists():
    """Check that the results.json file exists."""
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} is missing. The script did not generate the output."


def test_results_valid_json():
    """Check that results.json is valid JSON and a dictionary."""
    try:
        data = load_results()
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")
    assert isinstance(data, dict), f"JSON content in {RESULTS_PATH} must be a dictionary."


def test_results_keys_and_types():
    """Check that results.json contains exactly the required keys with correct types."""
    data = load_results()
    actual_keys = set(data.keys())
    missing_keys = EXPECTED_KEYS - actual_keys
    extra_keys = actual_keys - EXPECTED_KEYS

    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"
    assert not extra_keys, f"Extra keys in results.json: {extra_keys}"
    assert isinstance(data["n_components"], int) or (isinstance(data["n_components"], float) and data["n_components"].is_integer()), "n_components must be an integer."
    assert isinstance(data["best_alpha"], (int, float)), "best_alpha must be a float."
    assert isinstance(data["baseline_mean_mse"], (int, float)), "baseline_mean_mse must be a float."
    assert isinstance(data["pca_mean_mse"], (int, float)), "pca_mean_mse must be a float."
    assert isinstance(data["p_value"], (int, float)), "p_value must be a float."
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a float."
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a float."


def test_results_value_invariants():
    """Check that the values in results.json satisfy logical invariants."""
    data = load_results()
    assert 1 <= data["n_components"] <= 20, f"n_components ({data['n_components']}) is out of expected bounds [1, 20]."
    valid_alphas = {0.1, 1.0, 10.0, 100.0}
    assert any(abs(data["best_alpha"] - a) < 1e-6 for a in valid_alphas), f"best_alpha ({data['best_alpha']}) is not one of the expected grid values [0.1, 1.0, 10.0, 100.0]."
    assert data["baseline_mean_mse"] >= 0, "baseline_mean_mse must be non-negative."
    assert data["pca_mean_mse"] >= 0, "pca_mean_mse must be non-negative."
    assert 0.0 <= data["p_value"] <= 1.0, f"p_value ({data['p_value']}) must be between 0 and 1."
    assert data["ci_lower"] <= data["ci_upper"], f"ci_lower ({data['ci_lower']}) must be <= ci_upper ({data['ci_upper']})."


def test_results_match_recomputed_pipeline():
    """Independently recompute every requested statistic from the supplied CSVs."""
    actual = load_results()
    expected = compute_expected_results()

    assert int(actual["n_components"]) == expected["n_components"]
    assert float(actual["best_alpha"]) == pytest.approx(expected["best_alpha"], rel=0, abs=1e-12)

    for key in ("baseline_mean_mse", "pca_mean_mse", "p_value", "ci_lower", "ci_upper"):
        value = float(actual[key])
        assert math.isfinite(value), f"{key} must be finite."
        assert value == pytest.approx(expected[key], rel=1e-7, abs=1e-8), (
            f"{key} is incorrect: got {value}, expected {expected[key]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
