#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.stats import ttest_rel
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import KFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

DATA_PATH = "/home/user/data.csv"
SCRIPT_PATH = "/home/user/etl_pipeline.py"
RESULTS_PATH = "/home/user/results.json"
ORIGINAL_EXPECTED = None


def compute_expected(df):
    X = df.drop("target", axis=1)
    y = df["target"]

    imputer = SimpleImputer(strategy="mean")
    X_imputed = imputer.fit_transform(X)
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_imputed)

    model = LogisticRegression(random_state=42, max_iter=1000)
    cv = KFold(n_splits=10, shuffle=True, random_state=42)
    flawed_scores = cross_val_score(model, X_scaled, y, cv=cv, scoring="roc_auc")

    corrected_pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", StandardScaler()),
        ("model", LogisticRegression(random_state=42, max_iter=1000)),
    ])
    corrected_scores = cross_val_score(
        corrected_pipeline, X, y, cv=cv, scoring="roc_auc"
    )

    return {
        "flawed_mean_auc": float(np.mean(flawed_scores)),
        "corrected_mean_auc": float(np.mean(corrected_scores)),
        "p_value": float(ttest_rel(flawed_scores, corrected_scores).pvalue),
    }


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing"
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert completed.returncode == 0, (
        "etl_pipeline.py failed when executed:\n"
        + completed.stdout
        + completed.stderr
    )
    assert os.path.isfile(RESULTS_PATH), "etl_pipeline.py did not create results.json"
    with open(RESULTS_PATH, "r") as f:
        return json.load(f)


def assert_exact_results(actual, expected):
    expected_keys = {"flawed_mean_auc", "corrected_mean_auc", "p_value"}
    assert set(actual.keys()) == expected_keys
    for key in expected_keys:
        assert isinstance(actual[key], float), f"{key} must be a float"
        assert math.isfinite(actual[key]), f"{key} must be finite"
        assert math.isclose(actual[key], expected[key], rel_tol=1e-12, abs_tol=1e-12), (
            f"{key} is incorrect: got {actual[key]!r}, expected {expected[key]!r}"
        )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_submission():
    global ORIGINAL_EXPECTED

    with open(DATA_PATH, "rb") as f:
        original_bytes = f.read()
    original_df = pd.read_csv(DATA_PATH)
    ORIGINAL_EXPECTED = compute_expected(original_df)

    # Exercise the submitted script on an unpredictable row ordering so fixed
    # precomputed output cannot pass. The schema and modeling task are unchanged.
    rng = np.random.default_rng(secrets.randbits(64))
    order = rng.permutation(len(original_df))
    if np.array_equal(order, np.arange(len(original_df))):
        order = np.roll(order, 1)
    probe_df = original_df.iloc[order].reset_index(drop=True)
    probe_expected = compute_expected(probe_df)

    try:
        probe_df.to_csv(DATA_PATH, index=False)
        probe_actual = run_submission()
        assert_exact_results(probe_actual, probe_expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_bytes)

    # Leave results.json containing results for the original required dataset.
    final_actual = run_submission()
    assert_exact_results(final_actual, ORIGINAL_EXPECTED)
    yield


def test_results_json_exists():
    """Check that the results.json file was created."""
    assert os.path.isfile("/home/user/results.json"), "/home/user/results.json is missing"


def test_results_json_content():
    """Check the contents of results.json for correct keys and reasonable values."""
    with open("/home/user/results.json", "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/results.json is not valid JSON"

    expected_keys = {"flawed_mean_auc", "corrected_mean_auc", "p_value"}
    assert set(results.keys()) == expected_keys, f"results.json keys do not match expected. Got {list(results.keys())}"

    flawed_auc = results["flawed_mean_auc"]
    corrected_auc = results["corrected_mean_auc"]
    p_value = results["p_value"]

    assert isinstance(flawed_auc, float), "flawed_mean_auc must be a float"
    assert isinstance(corrected_auc, float), "corrected_mean_auc must be a float"
    assert isinstance(p_value, float), "p_value must be a float"

    # Preserve the original sanity assertions.
    assert math.isclose(flawed_auc, 0.8710, abs_tol=0.01), f"flawed_mean_auc {flawed_auc} is not within expected range (~0.8710)"
    assert math.isclose(corrected_auc, 0.8654, abs_tol=0.01), f"corrected_mean_auc {corrected_auc} is not within expected range (~0.8654)"
    assert corrected_auc < flawed_auc, "corrected_mean_auc should be lower than flawed_mean_auc due to removed data leakage"
    assert 0.0 <= p_value <= 1.0, f"p_value {p_value} is not a valid probability"

    # Verify all three values against independently recomputed results.
    assert_exact_results(results, ORIGINAL_EXPECTED)


def test_etl_pipeline_modified():
    """Check that the etl_pipeline.py script was modified to include a Pipeline."""
    assert os.path.isfile("/home/user/etl_pipeline.py"), "/home/user/etl_pipeline.py is missing"
    with open("/home/user/etl_pipeline.py", "r") as f:
        content = f.read()

    assert "Pipeline" in content or "make_pipeline" in content, "The ETL script does not seem to use a scikit-learn Pipeline"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
