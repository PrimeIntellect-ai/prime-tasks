#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pickle
import time
from pathlib import Path

import cv2
import joblib
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

API_URL = "http://127.0.0.1:8080/predict"
AUTH_TOKEN = "secret-token-123"


def wait_for_server(url, timeout=10):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.5)
    return False


def build_reference_pipeline():
    cap = cv2.VideoCapture("/app/experiment_feed.mp4")
    assert cap.isOpened(), "The experiment video could not be opened"
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert abs(fps - 24.0) < 0.1, f"Unexpected video frame rate: {fps}"

    per_second = {}
    frame_count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # OpenCV uses BGR, so channel 2 is red in RGB terminology.
        second = int(frame_count / fps)
        per_second.setdefault(second, []).append(float(frame[:, :, 2].mean()))
        frame_count += 1
    cap.release()

    assert frame_count == 240, f"Expected 240 video frames, found {frame_count}"
    video = pd.DataFrame({
        "timestamp": sorted(per_second),
        "red_intensity": [float(np.mean(per_second[s])) for s in sorted(per_second)],
    })
    assert len(video) == 10
    assert all(len(per_second[s]) == 24 for s in range(10))

    sensors = pd.read_csv("/app/sensor_logs.csv")
    with open("/app/metadata.json", "r", encoding="utf-8") as f:
        offset = json.load(f)["offset"]
    sensors = sensors.copy()
    sensors["timestamp"] = sensors["timestamp"] + offset
    joined = sensors.merge(video, on="timestamp", how="inner")
    assert len(joined) == 10, f"Expected 10 timestamp-aligned rows, found {len(joined)}"

    feature_columns = ["temp", "pressure", "humidity", "red_intensity"]
    corr = joined[feature_columns].corr(method="pearson")
    dropped = set()
    for i, earlier in enumerate(feature_columns):
        if earlier in dropped:
            continue
        for later in feature_columns[i + 1:]:
            if later not in dropped and abs(float(corr.loc[earlier, later])) > 0.90:
                dropped.add(later)
    kept = [name for name in feature_columns if name not in dropped]

    X = joined[kept]
    y = joined["target_yield"]
    search = GridSearchCV(Ridge(), {"alpha": [0.1, 1.0, 10.0]}, cv=5)
    search.fit(X, y)
    return joined, kept, search.best_estimator_, float(search.best_params_["alpha"])


JOINED, KEPT_FEATURES, REFERENCE_MODEL, EXPECTED_ALPHA = build_reference_pipeline()


def contains_ridge(obj):
    if isinstance(obj, Ridge):
        return True
    if isinstance(obj, dict):
        return any(contains_ridge(v) for v in obj.values())
    if hasattr(obj, "best_estimator_") and contains_ridge(obj.best_estimator_):
        return True
    if hasattr(obj, "steps"):
        return any(contains_ridge(v) for _, v in obj.steps)
    return False


def find_ridge(obj):
    if isinstance(obj, Ridge):
        return obj
    if isinstance(obj, dict):
        for value in obj.values():
            found = find_ridge(value)
            if found is not None:
                return found
    if hasattr(obj, "best_estimator_"):
        found = find_ridge(obj.best_estimator_)
        if found is not None:
            return found
    if hasattr(obj, "steps"):
        for _, value in obj.steps:
            found = find_ridge(value)
            if found is not None:
                return found
    return None


def predictor_from_object(obj):
    if isinstance(obj, dict):
        for key in ("model", "best_model", "estimator", "regressor"):
            value = obj.get(key)
            if value is not None and hasattr(value, "predict") and contains_ridge(value):
                return value
        for value in obj.values():
            if hasattr(value, "predict") and contains_ridge(value):
                return value
        return None
    if hasattr(obj, "predict") and contains_ridge(obj):
        return obj
    return None


def load_saved_model():
    candidates = []
    for root in (Path("/app"), Path("/home/user")):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                if not path.is_file() or path.stat().st_size > 20_000_000:
                    continue
            except OSError:
                continue
            lower = path.name.lower()
            if path.suffix.lower() in (".pkl", ".pickle", ".joblib", ".sav") or any(
                word in lower for word in ("model", "ridge", "estimator")
            ):
                candidates.append(path)

    failures = []
    for path in sorted(set(candidates)):
        for loader in (joblib.load, lambda p: pickle.load(open(p, "rb"))):
            try:
                obj = loader(path)
                predictor = predictor_from_object(obj)
                if predictor is not None:
                    return path, predictor, find_ridge(predictor)
            except Exception as exc:
                failures.append(f"{path}: {type(exc).__name__}")
    pytest.fail("No loadable saved Ridge model was found under /app or /home/user. " + "; ".join(failures[:5]))


def model_input(model, frame):
    names = getattr(model, "feature_names_in_", None)
    if names is None and hasattr(model, "best_estimator_"):
        names = getattr(model.best_estimator_, "feature_names_in_", None)
    if names is None:
        return frame[KEPT_FEATURES].to_numpy()

    values = {}
    for name in list(names):
        key = str(name)
        lowered = key.lower()
        if key in frame.columns:
            values[key] = frame[key].to_numpy()
        elif "red" in lowered:
            values[key] = frame["red_intensity"].to_numpy()
        elif lowered in frame.columns:
            values[key] = frame[lowered].to_numpy()
        else:
            pytest.fail(f"Saved model requires unexpected feature {key!r}")
    return pd.DataFrame(values)


def authorized_prediction(payload):
    response = requests.post(
        API_URL,
        json=payload,
        headers={"Authorization": f"Bearer {AUTH_TOKEN}", "Content-Type": "application/json"},
        timeout=5,
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "prediction" in data
    assert isinstance(data["prediction"], (int, float))
    assert math.isfinite(float(data["prediction"]))
    return float(data["prediction"])


def test_saved_model_pipeline_and_reference_behavior():
    path, saved_model, ridge = load_saved_model()
    assert path.is_file() and path.stat().st_size > 0
    assert ridge is not None, "Saved estimator is not a Ridge regression model"
    assert float(ridge.alpha) in (0.1, 1.0, 10.0), "Ridge alpha is outside the required grid"
    assert float(ridge.alpha) == pytest.approx(EXPECTED_ALPHA), "Saved alpha is not the 5-fold grid-search optimum"
    assert int(ridge.n_features_in_) == len(KEPT_FEATURES), (
        f"Model uses {ridge.n_features_in_} features, but correlation removal leaves {KEPT_FEATURES}"
    )

    saved_predictions = np.asarray(saved_model.predict(model_input(saved_model, JOINED)), dtype=float).reshape(-1)
    reference_predictions = np.asarray(REFERENCE_MODEL.predict(JOINED[KEPT_FEATURES]), dtype=float).reshape(-1)
    assert len(saved_predictions) == len(JOINED)
    assert np.all(np.isfinite(saved_predictions))
    assert np.max(np.abs(saved_predictions - reference_predictions)) < 0.15, (
        "Saved model predictions do not match the model derived from decoded red-channel frames, "
        "offset timestamp joining, correlation removal, and Ridge grid search"
    )

    assert wait_for_server(API_URL), "API server did not become available"
    for row_index in (0, 4, 9):
        row = JOINED.iloc[row_index]
        payload = {
            "temp": float(row["temp"]),
            "pressure": float(row["pressure"]),
            "humidity": float(row["humidity"]),
            "red_intensity": float(row["red_intensity"]),
        }
        actual = authorized_prediction(payload)
        assert actual == pytest.approx(float(saved_predictions[row_index]), abs=1e-4), (
            "API prediction does not use the saved trained model"
        )
        assert actual == pytest.approx(float(reference_predictions[row_index]), abs=0.15)


def test_api_predict_success():
    """Test the /predict endpoint with correct authentication and payload."""
    wait_for_server(API_URL)
    headers = {
        "Authorization": f"Bearer {AUTH_TOKEN}",
        "Content-Type": "application/json"
    }
    payload = {
        "temp": 25.5,
        "pressure": 1.2,
        "red_intensity": 150.4
    }
    try:
        response = requests.post(API_URL, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {API_URL}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "prediction" in data, f"Key 'prediction' not found in response JSON: {data}"
    assert isinstance(data["prediction"], (int, float)), f"Prediction value should be a number, got {type(data['prediction'])}"


def test_api_predict_unauthorized():
    """Test the /predict endpoint with missing or incorrect authentication."""
    wait_for_server(API_URL)
    headers = {
        "Authorization": "Bearer wrong-token",
        "Content-Type": "application/json"
    }
    payload = {
        "temp": 25.5,
        "pressure": 1.2,
        "red_intensity": 150.4
    }
    try:
        response = requests.post(API_URL, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {API_URL}: {e}")
    assert response.status_code in (401, 403), f"Expected status code 401 or 403 for unauthorized request, got {response.status_code}"


def test_api_predict_missing_auth():
    """Test the /predict endpoint with no authentication header."""
    wait_for_server(API_URL)
    headers = {"Content-Type": "application/json"}
    payload = {
        "temp": 25.5,
        "pressure": 1.2,
        "red_intensity": 150.4
    }
    try:
        response = requests.post(API_URL, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {API_URL}: {e}")
    assert response.status_code in (401, 403), f"Expected status code 401 or 403 for request missing auth header, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
