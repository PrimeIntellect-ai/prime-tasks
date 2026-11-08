#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import math
import os
import socket
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

DATA_PATH = "/home/user/sensor_data.csv"
PACKAGE_PATH = "/app/fast-corr-py"
HTTP_URL = "http://127.0.0.1:8080/predict"
AUTH_HEADERS = {"Authorization": "Bearer research_token"}


def build_expected_pipeline():
    df = pd.read_csv(DATA_PATH)
    feature_names = [c for c in df.columns if c != "target"]

    features = df[feature_names].copy()
    for column in feature_names:
        features[column] = features[column].fillna(features[column].median())

    means = features.mean(axis=0)
    stds = features.std(axis=0, ddof=0)
    zscores = (features - means) / stds
    keep = (zscores.abs() <= 3.0).all(axis=1)

    clean_x = features.loc[keep].copy()
    clean_y = df.loc[keep, "target"].astype(float)

    correlations = {
        column: float(np.corrcoef(clean_x[column].to_numpy(dtype=float), clean_y.to_numpy(dtype=float))[0, 1])
        for column in feature_names
    }
    selected = sorted(feature_names, key=lambda c: abs(correlations[c]), reverse=True)[:2]

    search = GridSearchCV(
        Ridge(),
        {"alpha": [0.1, 1.0, 10.0]},
        cv=5,
    )
    search.fit(clean_x[selected], clean_y)

    model = Ridge(alpha=float(search.best_params_["alpha"]))
    model.fit(clean_x[selected], clean_y)
    return clean_x, clean_y, selected, correlations, float(search.best_params_["alpha"]), model


@pytest.fixture(scope="module")
def expected_pipeline():
    return build_expected_pipeline()


def test_fast_corr_installed_and_setup_repaired(expected_pipeline):
    """The vendored setup must build, and the installed artifact must be a working extension."""
    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PACKAGE_PATH,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Vendored extension still cannot be built:\n{result.stdout}"

    try:
        import fast_corr
    except ImportError:
        pytest.fail("The fast_corr package is not installed or importable. Ensure setup.py was fixed and installed correctly.")

    origin = os.path.realpath(getattr(fast_corr, "__file__", ""))
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"fast_corr must be the compiled extension, not a Python substitute; imported {origin!r}"
    )

    # Preserve the original fixed-input/type assertion.
    x = np.array([1.0, 2.0, 3.0], dtype=np.float64)
    y = np.array([1.0, 2.0, 3.0], dtype=np.float64)
    try:
        corr = fast_corr.compute(x, y)
        assert isinstance(corr, float), "fast_corr.compute did not return a float."
        assert corr == pytest.approx(1.0, abs=1e-12)
    except Exception as exc:
        pytest.fail(f"fast_corr.compute failed when called: {exc}")

    cases = [
        (np.array([3.5, -1.0, 7.25, 2.0, 9.0]), np.array([-2.0, 4.0, 1.5, 8.0, 0.25])),
        (np.arange(20.0)[::2], np.array([8.0, 3.0, 5.0, -1.0, 2.0, 9.0, 4.0, 7.0, 0.0, 6.0])),
        (np.array([1.0, 2.0, 3.0, 4.0]), np.array([8.0, 6.0, 4.0, 2.0])),
    ]
    for a, b in cases:
        actual = fast_corr.compute(a, b)
        reference = float(np.corrcoef(a, b)[0, 1])
        assert isinstance(actual, float)
        assert actual == pytest.approx(reference, abs=1e-12)

    clean_x, clean_y, selected, correlations, _, _ = expected_pipeline
    for column in clean_x.columns:
        actual = fast_corr.compute(
            clean_x[column].to_numpy(dtype=np.float64),
            clean_y.to_numpy(dtype=np.float64),
        )
        assert actual == pytest.approx(correlations[column], abs=1e-10), (
            f"fast_corr returned the wrong cleaned-data correlation for {column}"
        )

    assert selected == ["f2", "f4"], f"Unexpected independently derived selected features: {selected}"


def test_tcp_health_service():
    """Verify the TCP health service responds to PING and then closes the connection."""
    host = "127.0.0.1"
    port = 8081
    try:
        with socket.create_connection((host, port), timeout=5) as sock:
            sock.settimeout(5)
            sock.sendall(b"PING\n")
            data = sock.recv(1024)
            response = data.decode("utf-8")
            assert response == "PONG\n", f"Expected 'PONG\\n', but got {response!r}"
            assert sock.recv(1) == b"", "TCP service did not close the connection after replying"
    except ConnectionRefusedError:
        pytest.fail(f"TCP connection refused on {host}:{port}. Is the health service running?")
    except socket.timeout:
        pytest.fail("TCP connection timed out waiting for a response or close.")


def test_http_auth_missing():
    payload = {"f2": 1.0, "f4": 1.0}
    try:
        response = requests.post(HTTP_URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("HTTP connection refused on port 8080. Is the API service running?")
    assert response.status_code == 401, f"Expected 401 Unauthorized when missing token, got {response.status_code}"


def test_http_auth_incorrect():
    payload = {"f2": 1.0, "f4": 1.0}
    headers = {"Authorization": "Bearer wrong_token"}
    response = requests.post(HTTP_URL, json=payload, headers=headers, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized with incorrect token, got {response.status_code}"


def test_http_predict_valid():
    """Preserve the original authorized prediction shape check."""
    payload = {"f2": 0.5, "f4": -0.5}
    try:
        response = requests.post(HTTP_URL, json=payload, headers=AUTH_HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
        data = response.json()
        assert "prediction" in data, f"Response JSON missing 'prediction' key. Got: {data}"
        assert isinstance(data["prediction"], (int, float)) and not isinstance(data["prediction"], bool), (
            "Prediction value must be a number."
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("HTTP connection refused on port 8080. Is the API service running?")
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"HTTP response was not valid JSON. Response text: {response.text}")


def test_http_predictions_match_cleaned_cv_ridge_pipeline(expected_pipeline):
    """Exercise the service on derived inputs and compare it with the required full pipeline."""
    clean_x, _, selected, _, best_alpha, model = expected_pipeline
    assert best_alpha in [0.1, 1.0, 10.0]

    rng = np.random.default_rng(20260911)
    sampled_positions = rng.choice(len(clean_x), size=5, replace=False)
    requests_to_check = [
        {name: float(clean_x.iloc[pos][name]) for name in selected}
        for pos in sampled_positions
    ]
    requests_to_check.extend([
        {selected[0]: 37.125, selected[1]: -24.75},
        {selected[0]: -61.5, selected[1]: 42.25},
        {selected[0]: 0.0, selected[1]: 0.0},
    ])

    expected_values = model.predict(pd.DataFrame(requests_to_check, columns=selected))
    observed = []
    for payload, expected in zip(requests_to_check, expected_values):
        response = requests.post(HTTP_URL, json=payload, headers=AUTH_HEADERS, timeout=5)
        assert response.status_code == 200, (
            f"Authorized prediction failed for selected features {selected}: "
            f"status={response.status_code}, body={response.text}"
        )
        body = response.json()
        assert set(body) == {"prediction"}, f"Expected only a prediction field, got {body}"
        value = body["prediction"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        value = float(value)
        assert math.isfinite(value), f"Prediction was not finite: {value}"
        tolerance = 1e-6 * max(1.0, abs(float(expected)))
        assert abs(value - float(expected)) <= tolerance, (
            f"Prediction {value} does not match the required cleaned/CV Ridge result "
            f"{float(expected)} for payload {payload}; selected={selected}, alpha={best_alpha}"
        )
        observed.append(value)

    assert max(observed) - min(observed) > 1.0, "Predictions do not vary with the supplied feature values"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
