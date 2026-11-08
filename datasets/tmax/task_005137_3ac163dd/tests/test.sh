#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pickle
import sys
import time

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

FEATURE_COLUMNS = [
    "num_samples",
    "num_features",
    "missing_ratio",
    "variance_score",
]
DATA_PATH = "/home/user/data/raw_datasets.csv"
MODEL_PATH = "/home/user/model.pkl"
SCALER_PATH = "/home/user/scaler.pkl"
METRICS_PATH = "/home/user/metrics.json"
URL = "http://127.0.0.1:8080/predict"
VALID_HEADERS = {"Authorization": "Bearer RESEARCH-SEC-2024"}


def load_artifacts():
    with open(MODEL_PATH, "rb") as f:
        model = pickle.load(f)
    with open(SCALER_PATH, "rb") as f:
        scaler = pickle.load(f)
    return model, scaler


def prescribed_training_state():
    df = pd.read_csv(DATA_PATH)
    X = df[FEATURE_COLUMNS]
    y = df["category"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = RandomForestClassifier(random_state=42)
    model.fit(X_train_scaled, y_train)
    return df, X_train_scaled, X_test_scaled, y_train, y_test, scaler, model


def test_datacleaner_fixed():
    vendored_path = "/app/vendored/datacleaner-1.0.0"
    if vendored_path not in sys.path:
        sys.path.insert(0, vendored_path)

    try:
        from datacleaner.core import prepare_and_split
    except ImportError:
        pytest.fail("Could not import prepare_and_split from datacleaner.core")

    # Distinct values make fitting before splitting observably different.
    X = np.column_stack([
        np.arange(100, dtype=float),
        np.arange(100, dtype=float) ** 2 + 3.0,
    ])
    y = np.arange(100) % 3

    try:
        result = prepare_and_split(X, y, test_size=0.2, random_state=42)
    except Exception as e:
        pytest.fail(f"prepare_and_split raised an exception: {e}")

    assert len(result) == 5, "prepare_and_split should return 5 items: X_train, X_test, y_train, y_test, scaler"
    X_train, X_test, y_train, y_test, scaler = result

    assert hasattr(scaler, "n_samples_seen_"), "Returned scaler does not appear to be a fitted StandardScaler"
    assert scaler.n_samples_seen_ == 80, f"Scaler should be fitted on 80 samples, but saw {scaler.n_samples_seen_}. This indicates data leakage."
    assert type(scaler).__name__ == "StandardScaler", "Returned scaler is not a StandardScaler"
    assert isinstance(scaler, StandardScaler), "Returned scaler is not an sklearn StandardScaler"

    raw_train, raw_test, expected_y_train, expected_y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    expected_scaler = StandardScaler().fit(raw_train)
    expected_train = expected_scaler.transform(raw_train)
    expected_test = expected_scaler.transform(raw_test)

    np.testing.assert_array_equal(np.asarray(y_train), expected_y_train)
    np.testing.assert_array_equal(np.asarray(y_test), expected_y_test)
    np.testing.assert_allclose(np.asarray(X_train), expected_train, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(np.asarray(X_test), expected_test, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(scaler.mean_, expected_scaler.mean_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.scale_, expected_scaler.scale_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(np.mean(np.asarray(X_train), axis=0), 0.0, atol=1e-12)


def test_model_and_scaler_exist_and_are_prescribed_fitted_artifacts():
    assert os.path.exists(MODEL_PATH), f"{MODEL_PATH} does not exist"
    assert os.path.exists(SCALER_PATH), f"{SCALER_PATH} does not exist"

    model, scaler = load_artifacts()
    assert type(model).__name__ == "RandomForestClassifier", "Model is not a RandomForestClassifier"
    assert isinstance(model, RandomForestClassifier), "Model is not an sklearn RandomForestClassifier"
    assert type(scaler).__name__ == "StandardScaler", "Scaler is not a StandardScaler"
    assert isinstance(scaler, StandardScaler), "Scaler is not an sklearn StandardScaler"

    assert hasattr(model, "estimators_") and len(model.estimators_) > 0, "Model is not fitted"
    assert hasattr(model, "classes_"), "Model is not fitted"
    assert hasattr(scaler, "mean_") and hasattr(scaler, "scale_"), "Scaler is not fitted"
    assert model.random_state == 42, "RandomForestClassifier must use random_state=42"

    _, expected_X_train, expected_X_test, expected_y_train, _, expected_scaler, expected_model = prescribed_training_state()
    assert scaler.n_samples_seen_ == len(expected_X_train), "Saved scaler was not fitted only on the training split"
    np.testing.assert_allclose(scaler.mean_, expected_scaler.mean_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.var_, expected_scaler.var_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.scale_, expected_scaler.scale_, rtol=0, atol=1e-12)
    assert getattr(scaler, "n_features_in_", None) == 4
    assert getattr(model, "n_features_in_", None) == 4
    np.testing.assert_array_equal(model.classes_, expected_model.classes_)

    # The prescribed random forest is deterministic. Compare both probabilities
    # and predictions over the entire held-out split, not merely one sample.
    np.testing.assert_allclose(
        model.predict_proba(expected_X_test),
        expected_model.predict_proba(expected_X_test),
        rtol=0,
        atol=1e-15,
    )
    np.testing.assert_array_equal(
        model.predict(expected_X_test), expected_model.predict(expected_X_test)
    )

    # Confirm the model also fits the specified training split rather than being
    # an unfitted or unrelated object with fabricated attributes.
    assert model.score(expected_X_train, expected_y_train) == pytest.approx(
        expected_model.score(expected_X_train, expected_y_train), abs=1e-15
    )


def test_metrics_json_exists_and_valid():
    assert os.path.exists(METRICS_PATH), f"{METRICS_PATH} does not exist"

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_PATH} is not valid JSON")

    assert "inference_time_seconds" in metrics, "Key 'inference_time_seconds' missing in metrics.json"
    value = metrics["inference_time_seconds"]
    assert isinstance(value, (int, float)), "inference_time_seconds must be a number"
    assert not isinstance(value, bool), "inference_time_seconds must be a numeric duration"
    assert np.isfinite(value) and value > 0, "inference_time_seconds must be finite and positive"

    model, _ = load_artifacts()
    _, _, X_test, _, _, _, _ = prescribed_training_state()
    start = time.perf_counter()
    for _ in range(100):
        model.predict(X_test)
    observed = time.perf_counter() - start

    # Timing varies, but a genuine benchmark of the same 100-call loop should
    # remain within a broad two-order-of-magnitude envelope.
    assert observed / 50.0 <= value <= observed * 50.0, (
        f"Recorded inference time {value} is not plausible for 100 full-test-set "
        f"predictions (verification measurement: {observed})"
    )


def test_web_service_auth_missing():
    payload = {"features": [1000, 20, 0.05, 1.2]}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to web service: {e}")
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"


def test_web_service_auth_incorrect():
    payload = {"features": [1000, 20, 0.05, 1.2]}
    headers = {"Authorization": "Bearer WRONG-TOKEN"}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to web service: {e}")
    assert response.status_code == 401, f"Expected 401 for incorrect auth, got {response.status_code}"


def test_web_service_success_matches_saved_model_on_multiple_inputs():
    model, scaler = load_artifacts()
    df = pd.read_csv(DATA_PATH)
    feature_vectors = [
        [1000, 20, 0.05, 1.2],
        df.loc[0, FEATURE_COLUMNS].astype(float).tolist(),
        df.loc[137, FEATURE_COLUMNS].astype(float).tolist(),
        df.loc[999, FEATURE_COLUMNS].astype(float).tolist(),
        [9500, 92, 0.47, 4.8],
    ]

    expected = model.predict(scaler.transform(np.asarray(feature_vectors, dtype=float)))
    for features, expected_prediction in zip(feature_vectors, expected):
        try:
            response = requests.post(
                URL,
                json={"features": features},
                headers=VALID_HEADERS,
                timeout=5,
            )
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to web service: {e}")

        assert response.status_code == 200, (
            f"Expected 200 for valid request, got {response.status_code}. Response: {response.text}"
        )
        try:
            data = response.json()
        except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
            pytest.fail(f"Response is not valid JSON: {response.text}")

        assert "prediction" in data, f"Key 'prediction' missing in response: {data}"
        assert isinstance(data["prediction"], int), f"Prediction should be an integer, got {type(data['prediction'])}"
        assert not isinstance(data["prediction"], bool), "Prediction must be an integer class, not a boolean"
        assert data["prediction"] == int(expected_prediction), (
            f"Service prediction {data['prediction']} does not match the saved scaler/model "
            f"prediction {int(expected_prediction)} for {features}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
