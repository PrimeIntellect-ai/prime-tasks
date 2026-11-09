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
import json
import math
import numbers
import os
import secrets
import socket

import joblib
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.utils.validation import check_is_fitted

ARTIFACT_PATH = "/home/user/artifacts/pipeline.joblib"
FEATURES = ["cpu_usage", "memory_mb", "disk_io", "network_rx"]


def get_redis_key(key):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(('127.0.0.1', 6379))
        cmd = f"*2\r\n$3\r\nGET\r\n${len(key)}\r\n{key}\r\n"
        s.sendall(cmd.encode('utf-8'))
        resp = s.recv(4096).decode('utf-8')
    finally:
        s.close()

    lines = resp.split('\r\n')
    if len(lines) >= 2 and lines[0].startswith('$') and lines[0] != '$-1':
        return lines[1]
    return None


@pytest.fixture(scope="session")
def artifact():
    assert os.path.isfile(ARTIFACT_PATH), f"Missing model artifact: {ARTIFACT_PATH}"
    data = joblib.load(ARTIFACT_PATH)
    assert isinstance(data, dict), "pipeline.joblib must contain a dictionary"

    ridge_models = [value for value in data.values() if isinstance(value, Ridge)]
    logistic_models = [value for value in data.values() if isinstance(value, LogisticRegression)]
    assert ridge_models, "Artifact dictionary does not contain a Ridge model"
    assert logistic_models, "Artifact dictionary does not contain a LogisticRegression model"

    ridge = ridge_models[0]
    logistic = logistic_models[0]
    check_is_fitted(ridge)
    check_is_fitted(logistic)
    assert getattr(ridge, "n_features_in_", None) == 4, "Ridge model was not fitted with four features"
    assert getattr(logistic, "n_features_in_", None) == 4, "LogisticRegression model was not fitted with four features"
    assert set(np.asarray(logistic.classes_).tolist()) == {0, 1}, "Classifier must be fitted on anomaly classes 0 and 1"

    medians = [
        float(value) for value in data.values()
        if isinstance(value, numbers.Real) and not isinstance(value, bool)
        and math.isclose(float(value), 1536.0, rel_tol=0.0, abs_tol=1e-9)
    ]
    assert medians, "Artifact dictionary does not contain the computed memory_mb median 1536.0"

    # Exercise both fitted estimators so a merely named or unfitted object cannot pass.
    probe = pd.DataFrame([[50.0, 2048.0, 200.0, 15.0]], columns=FEATURES)
    ridge_result = np.asarray(ridge.predict(probe)).reshape(-1)
    logistic_result = np.asarray(logistic.predict(probe)).reshape(-1)
    assert ridge_result.size == 1 and math.isfinite(float(ridge_result[0]))
    assert logistic_result.size == 1 and int(logistic_result[0]) in (0, 1)

    return {"ridge": ridge, "logistic": logistic, "median": medians[0]}


def expected_prediction(artifact, payload):
    memory = payload.get("memory_mb", artifact["median"])
    disk_io = payload["disk_io"]
    if disk_io > 1000.0:
        disk_io = 1000.0
    network_rx = payload.get("network_rx", 0.0)
    row = pd.DataFrame([[
        float(payload["cpu_usage"]),
        float(memory),
        float(disk_io),
        float(network_rx),
    ]], columns=FEATURES)
    latency = float(np.asarray(artifact["ridge"].predict(row)).reshape(-1)[0])
    anomaly = int(np.asarray(artifact["logistic"].predict(row)).reshape(-1)[0])
    return latency, anomaly


def post_valid(payload):
    try:
        return requests.post("http://127.0.0.1:8000/predict", json=payload, timeout=2.0)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to web service: {e}")


def assert_response_matches_models(response, artifact, payload):
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    resp_json = response.json()
    assert "latency_pred" in resp_json, "Response missing 'latency_pred'"
    assert "anomaly_pred" in resp_json, "Response missing 'anomaly_pred'"
    assert isinstance(resp_json["latency_pred"], float), "latency_pred must be a float"
    assert isinstance(resp_json["anomaly_pred"], int), "anomaly_pred must be an int"

    expected_latency, expected_anomaly = expected_prediction(artifact, payload)
    assert math.isclose(resp_json["latency_pred"], expected_latency, rel_tol=1e-7, abs_tol=1e-6), (
        f"latency_pred {resp_json['latency_pred']} does not match the saved Ridge model prediction {expected_latency}"
    )
    assert resp_json["anomaly_pred"] == expected_anomaly, (
        f"anomaly_pred {resp_json['anomaly_pred']} does not match the saved LogisticRegression prediction {expected_anomaly}"
    )


def test_artifact_exists_and_contains_fitted_models(artifact):
    assert artifact["median"] == 1536.0


def test_redis_metadata():
    """Verify the model metadata in Redis."""
    val = get_redis_key("model:latest")
    assert val is not None, "Redis key 'model:latest' not found or empty."

    try:
        data = json.loads(val)
    except json.JSONDecodeError:
        pytest.fail(f"Redis value is not valid JSON: {val}")

    assert data.get("status") == "trained", f"Expected status 'trained', got {data.get('status')}"
    assert data.get("path") == "/home/user/artifacts/pipeline.joblib", f"Expected path '/home/user/artifacts/pipeline.joblib', got {data.get('path')}"

    # The median of memory_mb (1024, 2048, 4096, 512) is 1536.0
    imputed_memory = data.get("imputed_memory")
    assert imputed_memory in (1536, 1536.0), f"Expected imputed_memory to be 1536.0, got {imputed_memory}"


def test_http_valid_request(artifact):
    """Test A: Valid Request with all fields"""
    payload = {"cpu_usage": 50.0, "memory_mb": 2048, "disk_io": 200.0, "network_rx": 15.0}
    r = post_valid(payload)

    assert r.status_code == 200, f"Expected HTTP 200, got {r.status_code}. Response: {r.text}"

    resp_json = r.json()
    assert "latency_pred" in resp_json, "Response missing 'latency_pred'"
    assert "anomaly_pred" in resp_json, "Response missing 'anomaly_pred'"
    assert isinstance(resp_json["latency_pred"], float), "latency_pred must be a float"
    assert isinstance(resp_json["anomaly_pred"], int), "anomaly_pred must be an int"
    assert_response_matches_models(r, artifact, payload)


def test_http_schema_out_of_bounds_cpu():
    """Test B: Schema Enforcement - Out of bounds cpu_usage"""
    payload = {"cpu_usage": 150.0, "memory_mb": 2048, "disk_io": 200.0}
    try:
        r = requests.post("http://127.0.0.1:8000/predict", json=payload, timeout=2.0)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to web service: {e}")

    assert r.status_code in (400, 422), f"Expected HTTP 400 or 422 for out-of-bounds cpu_usage, got {r.status_code}. Response: {r.text}"


def test_http_schema_invalid_memory_type():
    """Test C: Schema Enforcement - Invalid memory_mb value"""
    payload = {"cpu_usage": 50.0, "memory_mb": -100, "disk_io": 200.0}
    try:
        r = requests.post("http://127.0.0.1:8000/predict", json=payload, timeout=2.0)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to web service: {e}")

    assert r.status_code in (400, 422), f"Expected HTTP 400 or 422 for invalid memory_mb, got {r.status_code}. Response: {r.text}"


def test_http_missing_values_and_defaulting(artifact):
    """Test D: Missing Value Handling & Defaulting"""
    payload = {"cpu_usage": 80.0, "disk_io": 1500.0}
    r = post_valid(payload)

    assert r.status_code == 200, f"Expected HTTP 200 for payload with missing optional fields, got {r.status_code}. Response: {r.text}"

    resp_json = r.json()
    assert "latency_pred" in resp_json, "Response missing 'latency_pred'"
    assert "anomaly_pred" in resp_json, "Response missing 'anomaly_pred'"
    assert isinstance(resp_json["latency_pred"], float), "latency_pred must be a float"
    assert isinstance(resp_json["anomaly_pred"], int), "anomaly_pred must be an int"
    assert_response_matches_models(r, artifact, payload)


def test_http_predictions_match_saved_models_on_unpredictable_inputs(artifact):
    rng = secrets.SystemRandom()
    payloads = [
        {"cpu_usage": 0.0, "memory_mb": 1, "disk_io": 1000.0, "network_rx": 0.0},
        {"cpu_usage": 100.0, "memory_mb": 8192, "disk_io": 4321.25, "network_rx": 77.5},
    ]
    for index in range(6):
        payload = {
            "cpu_usage": rng.uniform(0.01, 99.99),
            "disk_io": rng.uniform(-250.0, 4000.0),
        }
        if index % 2 == 0:
            payload["memory_mb"] = rng.randint(1, 16384)
        if index % 3 != 0:
            payload["network_rx"] = rng.uniform(-100.0, 1000.0)
        payloads.append(payload)

    for payload in payloads:
        assert_response_matches_models(post_valid(payload), artifact, payload)


def test_disk_io_clipping_is_applied(artifact):
    base = {"cpu_usage": 37.25, "memory_mb": 3072, "network_rx": 19.75}
    at_limit = dict(base, disk_io=1000.0)
    above_limit = dict(base, disk_io=9876.5)
    first = post_valid(at_limit)
    second = post_valid(above_limit)
    assert_response_matches_models(first, artifact, at_limit)
    assert_response_matches_models(second, artifact, above_limit)
    assert first.json() == second.json(), "disk_io values above 1000.0 must be clipped to exactly 1000.0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
