#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.preprocessing import StandardScaler
from sklearn.utils import resample

DATA_PATH = "/home/user/sensor_data.csv"
RESULT_PATH = "/home/user/pipeline_results.json"


def test_pipeline_results_exists():
    """Verify that the pipeline_results.json file was created."""
    assert os.path.exists(RESULT_PATH), f"The results file is missing at {RESULT_PATH}."
    assert os.path.isfile(RESULT_PATH), f"The path {RESULT_PATH} exists but is not a file."


def test_pipeline_results_content():
    """Verify the contents of the pipeline_results.json file."""
    with open(RESULT_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULT_PATH} does not contain valid JSON.")

    expected_keys = {"balanced_rows", "explained_variance_sum", "roc_auc"}
    actual_keys = set(results.keys())
    assert expected_keys.issubset(actual_keys), \
        f"Missing keys in JSON. Expected {expected_keys}, found {actual_keys}."

    assert isinstance(results["balanced_rows"], int), "'balanced_rows' must be an integer."
    assert results["balanced_rows"] == 1900, \
        f"Expected 'balanced_rows' to be 1900, got {results['balanced_rows']}."

    assert isinstance(results["explained_variance_sum"], (float, int)), \
        "'explained_variance_sum' must be a float."
    expected_var_sum = 0.1585
    assert math.isclose(results["explained_variance_sum"], expected_var_sum, abs_tol=0.005), \
        f"Expected 'explained_variance_sum' to be approx {expected_var_sum}, got {results['explained_variance_sum']}."

    assert isinstance(results["roc_auc"], (float, int)), "'roc_auc' must be a float."
    expected_auc = 0.9427
    assert math.isclose(results["roc_auc"], expected_auc, abs_tol=0.005), \
        f"Expected 'roc_auc' to be approx {expected_auc}, got {results['roc_auc']}."


def _candidate_commands():
    excluded = {os.path.realpath(DATA_PATH), os.path.realpath(RESULT_PATH)}
    candidates = []

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            if os.path.realpath(path) in excluded:
                continue

            lower = name.lower()
            command = None
            if lower.endswith(".py"):
                command = [sys.executable, path]
            elif lower.endswith(".sh"):
                command = ["/bin/bash", path]
            elif lower.endswith(".r") and os.path.exists("/usr/bin/Rscript"):
                command = ["/usr/bin/Rscript", path]
            elif os.stat(path).st_mode & stat.S_IXUSR:
                command = [path]

            if command is not None:
                candidates.append((path, command))

    return candidates


def _make_challenge():
    seed = secrets.randbits(32)
    rng = np.random.default_rng(seed)
    n_majority = int(rng.integers(220, 281))
    n_minority = int(rng.integers(28, 46))
    n = n_majority + n_minority

    latent = rng.normal(size=(n, 4))
    loadings = rng.normal(scale=0.35, size=(4, 50))
    X = rng.normal(size=(n, 50)) + latent @ loadings
    y = np.zeros(n, dtype=int)
    minority_indices = rng.choice(n, size=n_minority, replace=False)
    y[minority_indices] = 1
    X[minority_indices, :8] += rng.uniform(0.8, 1.7, size=8)

    frame = pd.DataFrame(X, columns=[f"sensor_{i}" for i in range(1, 51)])
    frame.insert(0, "timestamp", pd.date_range("2025-01-01", periods=n, freq="h").astype(str))
    frame["failure"] = y
    return frame


def _reference_results(frame):
    feature_columns = [f"sensor_{i}" for i in range(1, 51)]
    standardized = StandardScaler().fit_transform(frame[feature_columns])
    work = pd.DataFrame(standardized, columns=feature_columns)
    work["failure"] = frame["failure"].to_numpy()

    majority = work[work["failure"] == 0]
    minority = work[work["failure"] == 1]
    minority_up = resample(
        minority,
        replace=True,
        n_samples=len(majority),
        random_state=42,
    )
    balanced = pd.concat([majority, minority_up], ignore_index=True)

    pca = PCA(n_components=5, random_state=42)
    components = pca.fit_transform(balanced[feature_columns])
    model = LogisticRegression(random_state=42)
    model.fit(components, balanced["failure"])
    probabilities = model.predict_proba(components)[:, 1]

    return {
        "balanced_rows": int(len(balanced)),
        "explained_variance_sum": round(float(pca.explained_variance_ratio_.sum()), 4),
        "roc_auc": round(float(roc_auc_score(balanced["failure"], probabilities)), 4),
    }


def _valid_dynamic_result(expected):
    if not os.path.isfile(RESULT_PATH):
        return False
    try:
        with open(RESULT_PATH, "r") as f:
            result = json.load(f)
    except (OSError, json.JSONDecodeError, TypeError):
        return False

    required = {"balanced_rows", "explained_variance_sum", "roc_auc"}
    if not required.issubset(result):
        return False
    if not isinstance(result["balanced_rows"], int):
        return False
    if result["balanced_rows"] != expected["balanced_rows"]:
        return False
    for key in ("explained_variance_sum", "roc_auc"):
        value = result[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False
        if not math.isfinite(float(value)):
            return False
        if not math.isclose(float(value), expected[key], abs_tol=0.00015):
            return False
    return True


def test_pipeline_script_executes_on_derived_input():
    candidates = _candidate_commands()
    assert candidates, "No executable pipeline script was found under /home/user."

    original_data = open(DATA_PATH, "rb").read()
    original_result = open(RESULT_PATH, "rb").read()
    challenge = _make_challenge()
    expected = _reference_results(challenge)
    attempts = []

    try:
        for path, command in candidates:
            challenge.to_csv(DATA_PATH, index=False)
            if os.path.lexists(RESULT_PATH):
                os.remove(RESULT_PATH)
            try:
                completed = subprocess.run(
                    command,
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=120,
                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                )
                attempts.append(f"{path}: exit {completed.returncode}")
            except (OSError, subprocess.TimeoutExpired) as exc:
                attempts.append(f"{path}: {type(exc).__name__}")
                continue

            if completed.returncode == 0 and _valid_dynamic_result(expected):
                return

        pytest.fail(
            "No submitted script produced correct results when executed on a derived "
            "sensor dataset. Attempts: " + "; ".join(attempts)
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        with open(RESULT_PATH, "wb") as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
