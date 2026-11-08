#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import importlib.metadata
import math
import os
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.neural_network import MLPRegressor

API_URL = "http://127.0.0.1:8000/predict"
AUTH_HEADER = {"Authorization": "Bearer secret-ds-token-8819"}
DATA_PATH = "/home/user/train_data.csv"


def test_pyjanitor_bug_fixed():
    """Keep the source assertion and exercise both the vendored and installed package."""
    filepath = "/app/pyjanitor/janitor/functions/fill.py"
    assert os.path.exists(filepath), f"File {filepath} not found."
    with open(filepath, "r") as f:
        content = f.read()

    assert "df.loc[df[column_name].isna(), column_name] = np.nan" not in content, \
        "The deliberate bug in pyjanitor's fill_empty function is still present."

    try:
        importlib.metadata.version("pyjanitor")
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("The fixed vendored pyjanitor package was not installed.")

    check_code = r'''
import numpy as np
import pandas as pd
import janitor

df = pd.DataFrame({
    "integer_col": pd.Series([7, pd.NA, -2], dtype="Int64"),
    "float_col": [1.5, np.nan, 2.5],
})
out = df.fill_empty(column_names=["integer_col", "float_col"], value=0)
assert str(out["integer_col"].dtype) == "Int64", out.dtypes
assert out["integer_col"].tolist() == [7, 0, -2], out
assert out["float_col"].tolist() == [1.5, 0.0, 2.5], out
assert not out.isna().any().any(), out
'''

    base_env = os.environ.copy()
    base_env.pop("PYTHONPATH", None)
    installed = subprocess.run(
        [sys.executable, "-c", check_code], cwd="/tmp", env=base_env,
        text=True, capture_output=True, timeout=30
    )
    assert installed.returncode == 0, \
        f"Installed pyjanitor does not have the required behavior:\n{installed.stdout}\n{installed.stderr}"

    source_env = base_env.copy()
    source_env["PYTHONPATH"] = "/app/pyjanitor"
    vendored = subprocess.run(
        [sys.executable, "-c", check_code], cwd="/tmp", env=source_env,
        text=True, capture_output=True, timeout=30
    )
    assert vendored.returncode == 0, \
        f"Vendored pyjanitor source is not correctly fixed:\n{vendored.stdout}\n{vendored.stderr}"


def _post(payload, headers=None, timeout=15):
    try:
        return requests.post(API_URL, headers=headers, json=payload, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Could not call the API server on port 8000: {exc}")


def test_api_missing_auth():
    response = _post({"dummy": 1})
    assert response.status_code in (401, 403), \
        f"Expected 401 or 403 for missing auth, got {response.status_code}"


def test_api_invalid_auth():
    response = _post(
        {"dummy": 1},
        headers={"Authorization": "Bearer wrong-token-123"},
    )
    assert response.status_code in (401, 403), \
        f"Expected 401 or 403 for invalid auth, got {response.status_code}"


@pytest.fixture(scope="session")
def reference_ensemble():
    assert os.path.exists(DATA_PATH), f"Dataset {DATA_PATH} is missing."

    # Preserve the integer nature of the three feature columns while filling the
    # nullable integer column exactly as required by the task.
    raw = pd.read_csv(
        DATA_PATH,
        dtype={"feat1": "Int64", "feat2": "Int64", "feat3": "Int64"},
    )
    cleaned = raw.fillna(0)
    assert not cleaned.isna().any().any()
    for name in ("feat1", "feat2", "feat3"):
        assert pd.api.types.is_integer_dtype(cleaned[name].dtype)

    feature_names = [c for c in cleaned.columns if c != "target"]
    models = []
    for i in range(10):
        boot = cleaned.sample(n=len(cleaned), replace=True, random_state=i)
        model = MLPRegressor(
            hidden_layer_sizes=(32, 16),
            activation="relu",
            max_iter=500,
            random_state=i,
        )
        model.fit(
            boot[feature_names].to_numpy(dtype=float),
            boot["target"].to_numpy(dtype=float),
        )
        models.append(model)

    return feature_names, models


def test_api_prediction_endpoint(reference_ensemble):
    """Compare the service to the required ten-model bootstrap ensemble."""
    feature_names, models = reference_ensemble

    # Include the original first-row case from the old verifier.
    with open(DATA_PATH, "r") as f:
        row = next(csv.DictReader(f))
    first = {}
    for key in feature_names:
        value = row[key]
        try:
            first[key] = float(value) if value.strip() else 0.0
        except ValueError:
            first[key] = 0.0

    # Additional verifier-selected points prevent a constant-response server
    # from satisfying the behavioral check.
    rng = secrets.SystemRandom()
    queries = [first]
    for _ in range(6):
        queries.append({name: rng.randint(0, 99) for name in feature_names})

    expected_means = []
    for features in queries:
        vector = np.asarray([[features[name] for name in feature_names]], dtype=float)
        predictions = np.asarray(
            [float(model.predict(vector)[0]) for model in models], dtype=float
        )
        expected_mean = float(np.mean(predictions))
        expected_uncertainty = float(np.std(predictions, ddof=1))
        expected_means.append(expected_mean)

        response = _post(features, headers=AUTH_HEADER)
        assert response.status_code == 200, \
            f"Expected 200 OK for valid request, got {response.status_code}. Response: {response.text}"

        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")

        assert "mean_prediction" in data, "Response JSON is missing 'mean_prediction' key."
        assert "uncertainty" in data, "Response JSON is missing 'uncertainty' key."
        assert isinstance(data["mean_prediction"], (int, float)), \
            f"'mean_prediction' should be a float, got {type(data['mean_prediction'])}"
        assert isinstance(data["uncertainty"], (int, float)), \
            f"'uncertainty' should be a float, got {type(data['uncertainty'])}"
        assert math.isfinite(float(data["mean_prediction"]))
        assert math.isfinite(float(data["uncertainty"]))
        assert float(data["uncertainty"]) >= 0
        assert np.isclose(
            float(data["mean_prediction"]), expected_mean, rtol=1e-5, atol=1e-6
        ), f"Incorrect ensemble mean for {features}: expected {expected_mean}, got {data['mean_prediction']}"
        assert np.isclose(
            float(data["uncertainty"]), expected_uncertainty, rtol=1e-5, atol=1e-6
        ), f"Incorrect sample standard deviation for {features}: expected {expected_uncertainty}, got {data['uncertainty']}"

    assert np.ptp(np.asarray(expected_means)) > 1e-6
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
