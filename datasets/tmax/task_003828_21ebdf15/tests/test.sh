#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "joblib:joblib"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import sys

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.impute import KNNImputer
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error, r2_score

TRAIN_FILE = "/home/user/pipeline/train.py"
REQ_FILE = "/home/user/pipeline/requirements.txt"
DATA_FILE = "/home/user/data/raw_data.csv"
MODEL_FILE = "/home/user/artifacts/model.pkl"
METRICS_FILE = "/home/user/artifacts/metrics.json"
FEATURES = ["f1", "f2", "f3"]


def expected_result(frame):
    X_imputed = KNNImputer(n_neighbors=3).fit_transform(frame[FEATURES])
    y = frame["target"].to_numpy()
    median = np.median(y)
    mad = np.median(np.abs(y - median))
    if mad == 0:
        keep = np.ones(len(y), dtype=bool)
    else:
        modified_z = 0.6745 * (y - median) / mad
        keep = np.abs(modified_z) <= 3.5

    expected_model = Ridge(alpha=1.0)
    expected_model.fit(X_imputed[keep], y[keep])
    predictions = expected_model.predict(X_imputed[keep])
    expected_metrics = {
        "mse": float(mean_squared_error(y[keep], predictions)),
        "r2": float(r2_score(y[keep], predictions)),
    }
    return expected_model, expected_metrics, X_imputed[keep]


def run_pipeline():
    for path in (MODEL_FILE, METRICS_FILE):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        [sys.executable, TRAIN_FILE],
        cwd="/home/user/pipeline",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"train.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MODEL_FILE), f"Model artifact missing after running train.py: {MODEL_FILE}"
    assert os.path.isfile(METRICS_FILE), f"Metrics artifact missing after running train.py: {METRICS_FILE}"


def validate_generated_artifacts(frame):
    expected_model, expected_metrics, cleaned_X = expected_result(frame)

    model = joblib.load(MODEL_FILE)
    assert isinstance(model, Ridge), f"model.pkl must contain sklearn.linear_model.Ridge, got {type(model)}"
    assert float(model.alpha) == pytest.approx(1.0, abs=0.0), f"Ridge alpha must be 1.0, got {model.alpha}"
    np.testing.assert_allclose(model.coef_, expected_model.coef_, rtol=1e-8, atol=1e-8)
    np.testing.assert_allclose(model.intercept_, expected_model.intercept_, rtol=1e-8, atol=1e-8)
    np.testing.assert_allclose(
        model.predict(cleaned_X), expected_model.predict(cleaned_X), rtol=1e-8, atol=1e-8
    )

    with open(METRICS_FILE, "r") as f:
        metrics = json.load(f)
    assert set(metrics) == {"mse", "r2"}, "metrics.json must contain exactly the keys 'mse' and 'r2'"
    assert type(metrics["mse"]) is float, "'mse' must be a JSON float"
    assert type(metrics["r2"]) is float, "'r2' must be a JSON float"
    assert np.isfinite(metrics["mse"]) and np.isfinite(metrics["r2"])
    assert metrics["mse"] == pytest.approx(expected_metrics["mse"], rel=1e-8, abs=1e-8)
    assert metrics["r2"] == pytest.approx(expected_metrics["r2"], rel=1e-8, abs=1e-8)


@pytest.fixture(scope="session", autouse=True)
def execute_and_verify_pipeline():
    assert os.path.isfile(TRAIN_FILE), f"Pipeline script missing: {TRAIN_FILE}"
    with open(TRAIN_FILE, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=TRAIN_FILE)
    referenced = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
    referenced.update(
        alias.name.split(".")[-1]
        for node in ast.walk(tree)
        if isinstance(node, (ast.Import, ast.ImportFrom))
        for alias in node.names
    )
    referenced.update(node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute))
    assert "KNNImputer" in referenced, "train.py must use sklearn KNNImputer"
    assert "Ridge" in referenced, "train.py must use sklearn Ridge"

    with open(DATA_FILE, "rb") as f:
        original_data = f.read()

    rng = np.random.default_rng(73129)
    n = 90
    f1 = rng.normal(1.0, 1.8, n)
    f2 = rng.normal(-2.0, 2.5, n)
    f3 = rng.normal(4.0, 0.9, n)
    target = -2.2 * f1 + 0.65 * f2 + 1.7 * f3 + rng.normal(0, 0.3, n)
    f1[[2, 17, 41, 72]] = np.nan
    f2[[8, 29, 57]] = np.nan
    f3[[4, 22, 38, 66, 81]] = np.nan
    target[[11, 63]] += np.array([140.0, -160.0])
    probe = pd.DataFrame({"f1": f1, "f2": f2, "f3": f3, "target": target})

    try:
        probe.to_csv(DATA_FILE, index=False)
        run_pipeline()
        validate_generated_artifacts(probe)
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)

    original_frame = pd.read_csv(DATA_FILE)
    run_pipeline()
    validate_generated_artifacts(original_frame)


def test_requirements_file_exists():
    """Test that the requirements.txt file was created."""
    req_file = "/home/user/pipeline/requirements.txt"
    assert os.path.isfile(req_file), f"Requirements file missing: {req_file}"
    with open(req_file, "r") as f:
        requirements = f.read().lower().replace("_", "-")
    for package in ("pandas", "numpy", "scikit-learn"):
        assert package in requirements, f"Required package '{package}' missing from requirements.txt"


def test_artifacts_exist():
    """Test that the model and metrics artifacts were generated."""
    model_file = "/home/user/artifacts/model.pkl"
    metrics_file = "/home/user/artifacts/metrics.json"

    assert os.path.isfile(model_file), f"Model artifact missing: {model_file}"
    assert os.path.isfile(metrics_file), f"Metrics artifact missing: {metrics_file}"


def test_metrics_values():
    """Test that the metrics.json contains the correct mse and r2 values."""
    metrics_file = "/home/user/artifacts/metrics.json"

    with open(metrics_file, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file {metrics_file} is not valid JSON.")

    assert "mse" in metrics, "Key 'mse' missing in metrics.json"
    assert "r2" in metrics, "Key 'r2' missing in metrics.json"

    mse = metrics["mse"]
    r2 = metrics["r2"]

    assert isinstance(mse, (float, int)), f"'mse' should be a float, got {type(mse)}"
    assert isinstance(r2, (float, int)), f"'r2' should be a float, got {type(r2)}"

    expected_mse = 0.2338
    expected_r2 = 0.9856

    assert abs(float(mse) - expected_mse) < 0.01, f"MSE {mse} is not within 0.01 of expected {expected_mse}"
    assert abs(float(r2) - expected_r2) < 0.01, f"R2 {r2} is not within 0.01 of expected {expected_r2}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
