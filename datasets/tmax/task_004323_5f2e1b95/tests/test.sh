#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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
import os
import pickle
import secrets
import stat
import subprocess
from pathlib import Path

import numpy as np
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

URL = "http://127.0.0.1:8000/predict"
TOKEN = "project zeus pipeline"
TEST_FEATURES = [1.5, 0.5, 2.0, 1.0, 3.0]
ETL_PATH = Path("/home/user/etl.py")
MODEL_PATH = Path("/home/user/model.pkl")


def build_reference():
    np.random.seed(1337)
    X = np.random.exponential(scale=2.0, size=(1000, 5))
    y = X[:, 0] * 3.5 + X[:, 1] * 1.2 - X[:, 2] * 0.5 + np.random.randn(1000) * 0.5

    X_train_raw, _, y_train, _ = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train_raw)
    model = Ridge(alpha=1.0)
    model.fit(X_train, y_train)
    return scaler, model


REFERENCE_SCALER, REFERENCE_MODEL = build_reference()


@pytest.fixture(scope="module", autouse=True)
def verify_etl_and_model_artifact():
    assert ETL_PATH.exists(), f"Missing required ETL script: {ETL_PATH}"
    assert ETL_PATH.is_file() and not ETL_PATH.is_symlink(), f"{ETL_PATH} must be a regular file"

    if MODEL_PATH.is_symlink() or MODEL_PATH.is_file():
        MODEL_PATH.unlink()
    elif MODEL_PATH.exists():
        pytest.fail(f"{MODEL_PATH} exists but is not a regular file")

    try:
        result = subprocess.run(
            ["python3", str(ETL_PATH)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("etl.py did not finish within 60 seconds")

    assert result.returncode == 0, (
        f"etl.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert MODEL_PATH.exists(), "Running etl.py did not create /home/user/model.pkl"
    mode = MODEL_PATH.lstat().st_mode
    assert stat.S_ISREG(mode) and not MODEL_PATH.is_symlink(), "model.pkl must be a regular file"

    try:
        with MODEL_PATH.open("rb") as f:
            artifact = pickle.load(f)
    except Exception as exc:
        pytest.fail(f"Could not load /home/user/model.pkl: {exc}")

    assert isinstance(artifact, tuple) and len(artifact) == 2, (
        "model.pkl must contain a (scaler, model) tuple"
    )
    scaler, model = artifact
    assert isinstance(scaler, StandardScaler), "Saved scaler is not a StandardScaler"
    assert isinstance(model, Ridge), "Saved model is not a Ridge model"

    np.testing.assert_allclose(scaler.mean_, REFERENCE_SCALER.mean_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(scaler.scale_, REFERENCE_SCALER.scale_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(model.coef_, REFERENCE_MODEL.coef_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(model.intercept_, REFERENCE_MODEL.intercept_, rtol=1e-10, atol=1e-10)


@pytest.fixture(scope="module")
def expected_prediction():
    x_in = np.array([TEST_FEATURES])
    x_in_scaled = REFERENCE_SCALER.transform(x_in)
    return REFERENCE_MODEL.predict(x_in_scaled)[0]


def test_api_unauthorized_no_token():
    """Verify that the API returns 401 when no token is provided."""
    try:
        response = requests.post(URL, json={"features": TEST_FEATURES}, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {URL}. Is the service running?")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_api_unauthorized_invalid_token():
    """Verify that the API returns 401 when an invalid token is provided."""
    headers = {"Authorization": "Bearer invalid token"}
    try:
        response = requests.post(URL, json={"features": TEST_FEATURES}, headers=headers, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {URL}. Is the service running?")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_api_authorized_prediction(expected_prediction):
    """Verify that the API returns the correct prediction with the valid token."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.post(URL, json={"features": TEST_FEATURES}, headers=headers, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {URL}. Is the service running?")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "prediction" in data, "Response JSON does not contain 'prediction' key"

    prediction = data["prediction"]
    assert isinstance(prediction, (int, float)), "Prediction is not a number"

    diff = abs(prediction - expected_prediction)
    assert diff < 1e-4, f"Prediction {prediction} is not within 1e-4 of expected {expected_prediction}"


def test_api_predictions_on_unannounced_inputs():
    """Exercise real scaling and model inference on inputs generated at verification time."""
    rng = secrets.SystemRandom()
    feature_vectors = [
        [rng.uniform(-3.0, 12.0) for _ in range(5)]
        for _ in range(8)
    ]
    expected = REFERENCE_MODEL.predict(
        REFERENCE_SCALER.transform(np.asarray(feature_vectors, dtype=float))
    )
    headers = {"Authorization": f"Bearer {TOKEN}"}

    for features, expected_value in zip(feature_vectors, expected):
        try:
            response = requests.post(
                URL, json={"features": features}, headers=headers, timeout=10
            )
        except requests.exceptions.ConnectionError:
            pytest.fail(f"Could not connect to the API at {URL}. Is the service running?")

        assert response.status_code == 200, (
            f"Expected 200 OK for features {features}, got {response.status_code}. "
            f"Response: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail("Response is not valid JSON")
        assert "prediction" in data, "Response JSON does not contain 'prediction' key"
        prediction = data["prediction"]
        assert isinstance(prediction, (int, float)), "Prediction is not a number"
        assert np.isfinite(prediction), "Prediction is not finite"
        assert abs(prediction - float(expected_value)) < 1e-4, (
            f"Prediction {prediction} is not within 1e-4 of expected {expected_value} "
            f"for features {features}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
