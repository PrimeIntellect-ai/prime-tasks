#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import time

import numpy as np
import pytest
import requests
from sklearn.naive_bayes import GaussianNB
from sklearn.preprocessing import StandardScaler

SERVICE_URL = "http://127.0.0.1:8080"


def get_expected_metrics():
    data_a = [{"user_id": i, "feature_1": i * 0.1, "target": i % 2} for i in range(100)]
    data_b = [{"user_id": i, "feature_2": i * -0.05} for i in range(100)]

    data = []
    for a in data_a:
        for b in data_b:
            if a["user_id"] == b["user_id"]:
                data.append({**a, **b})
                break
    data.sort(key=lambda x: x["user_id"])

    X = np.array([[d["feature_1"], d["feature_2"]] for d in data])
    y = np.array([d["target"] for d in data])
    split_index = int(len(data) * 0.8)
    X_train, X_test = X[:split_index], X[split_index:]
    y_train, y_test = y[:split_index], y[split_index:]

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    clf = GaussianNB()
    clf.fit(X_train_scaled, y_train)

    acc = clf.score(X_test_scaled, y_test)
    point = scaler.transform(np.array([[1.5, -0.5]]))
    prob = clf.predict_proba(point)[0][1]
    return round(float(acc), 4), round(float(prob), 4)


def test_01_artifact_exists():
    path = "/app/services/model_service.py"
    assert os.path.isfile(path), f"Required service artifact does not exist: {path}"
    assert not os.path.islink(path), f"Service artifact must be a regular file, not a symlink: {path}"
    assert os.path.getsize(path) > 0, f"Service artifact is empty: {path}"


def test_02_metrics_endpoint():
    expected_acc, _ = get_expected_metrics()
    try:
        response = requests.get(f"{SERVICE_URL}/metrics", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /metrics endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /metrics is not valid JSON: {response.text}")

    assert "test_accuracy" in data, f"Response missing 'test_accuracy' key: {data}"
    actual_acc = data["test_accuracy"]
    assert isinstance(actual_acc, (int, float)), f"'test_accuracy' must be a float, got {type(actual_acc)}"
    assert round(actual_acc, 4) == expected_acc, f"Expected test_accuracy {expected_acc}, got {actual_acc}"


def test_03_predict_endpoint():
    _, expected_prob = get_expected_metrics()
    payload = {"feature_1": 1.5, "feature_2": -0.5}
    try:
        response = requests.post(f"{SERVICE_URL}/predict", json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /predict endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /predict is not valid JSON: {response.text}")

    assert "probability_class_1" in data, f"Response missing 'probability_class_1' key: {data}"
    actual_prob = data["probability_class_1"]
    assert isinstance(actual_prob, (int, float)), f"'probability_class_1' must be a float, got {type(actual_prob)}"
    assert round(actual_prob, 4) == expected_prob, f"Expected probability_class_1 {expected_prob}, got {actual_prob}"


def _stop_existing_services():
    patterns = [
        "/app/services/api_a.py",
        "/app/services/api_b.py",
        "/app/services/model_service.py",
    ]
    for pattern in patterns:
        subprocess.run(["pkill", "-f", pattern], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)


def _wait_for_service(proc, timeout=25):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out, _ = proc.communicate(timeout=2)
            pytest.fail(f"model_service.py exited before serving requests (code {proc.returncode}):\n{out}")
        try:
            response = requests.get(f"{SERVICE_URL}/metrics", timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    pytest.fail(f"Fresh model_service.py did not become ready: {last_error}")


def test_04_fresh_service_uses_upstream_data_and_generalizes_predictions(tmp_path):
    # Use secret, verifier-generated upstream records in shuffled order, including
    # unmatched IDs. Expected values are independently derived from their inner join.
    rng = random.Random(917341)
    joined = []
    for i in range(67):
        user_id = 2003 + i * 7
        target = (i * 5 + 1) % 2
        feature_1 = target * 1.7 + rng.uniform(-0.75, 0.75) + i * 0.006
        feature_2 = -target * 1.15 + rng.uniform(-0.9, 0.9) - i * 0.004
        joined.append({
            "user_id": user_id,
            "feature_1": feature_1,
            "feature_2": feature_2,
            "target": target,
        })

    users = [{"user_id": d["user_id"], "feature_1": d["feature_1"], "target": d["target"]} for d in joined]
    transactions = [{"user_id": d["user_id"], "feature_2": d["feature_2"]} for d in joined]
    users.extend([
        {"user_id": 11, "feature_1": 9999.0, "target": 1},
        {"user_id": 12, "feature_1": -9999.0, "target": 0},
    ])
    transactions.extend([
        {"user_id": 901, "feature_2": 7777.0},
        {"user_id": 902, "feature_2": -7777.0},
    ])
    rng.shuffle(users)
    rng.shuffle(transactions)

    ordered = sorted(joined, key=lambda d: d["user_id"])
    X = np.array([[d["feature_1"], d["feature_2"]] for d in ordered], dtype=float)
    y = np.array([d["target"] for d in ordered])
    split = int(len(ordered) * 0.8)
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X[:split])
    X_test = scaler.transform(X[split:])
    model = GaussianNB()
    model.fit(X_train, y[:split])
    expected_accuracy = round(float(model.score(X_test, y[split:])), 4)

    query_points = [
        [-1.2, 1.4],
        [-0.25, 0.15],
        [0.55, -0.4],
        [1.25, -1.1],
        [2.1, -1.8],
        [0.9, 0.8],
        [2.8, 0.2],
    ]
    expected_probs = [
        round(float(p), 4)
        for p in model.predict_proba(scaler.transform(np.array(query_points, dtype=float)))[:, 1]
    ]

    mock_path = tmp_path / "mock_upstreams.py"
    mock_path.write_text(
        "from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler\n"
        "import json, threading\n"
        f"users = {users!r}\n"
        f"transactions = {transactions!r}\n"
        "class Users(BaseHTTPRequestHandler):\n"
        "    def do_GET(self):\n"
        "        body=json.dumps(users).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)\n"
        "    def log_message(self, *args): pass\n"
        "class Transactions(BaseHTTPRequestHandler):\n"
        "    def do_GET(self):\n"
        "        body=json.dumps(transactions).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)\n"
        "    def log_message(self, *args): pass\n"
        "a=ThreadingHTTPServer(('127.0.0.1',8001),Users)\n"
        "b=ThreadingHTTPServer(('127.0.0.1',8002),Transactions)\n"
        "threading.Thread(target=a.serve_forever,daemon=True).start()\n"
        "b.serve_forever()\n"
    )

    _stop_existing_services()
    mock_proc = subprocess.Popen(
        [sys.executable, str(mock_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    service_proc = None
    try:
        time.sleep(0.75)
        if mock_proc.poll() is not None:
            out, _ = mock_proc.communicate(timeout=2)
            pytest.fail(f"Could not start controlled upstream APIs:\n{out}")

        service_proc = subprocess.Popen(
            [sys.executable, "/app/services/model_service.py"],
            cwd="/app/services",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
        _wait_for_service(service_proc)

        metrics_response = requests.get(f"{SERVICE_URL}/metrics", timeout=5)
        assert metrics_response.status_code == 200
        metrics = metrics_response.json()
        assert "test_accuracy" in metrics
        assert isinstance(metrics["test_accuracy"], (int, float))
        assert round(metrics["test_accuracy"], 4) == expected_accuracy, (
            f"Fresh service returned accuracy {metrics['test_accuracy']}; expected {expected_accuracy} "
            "from the controlled upstream inner join and ordered 80/20 split"
        )

        for point, expected in zip(query_points, expected_probs):
            response = requests.post(
                f"{SERVICE_URL}/predict",
                json={"feature_1": point[0], "feature_2": point[1]},
                timeout=5,
            )
            assert response.status_code == 200, response.text
            result = response.json()
            assert "probability_class_1" in result
            actual = result["probability_class_1"]
            assert isinstance(actual, (int, float))
            assert round(actual, 4) == expected, (
                f"For prediction input {point}, expected {expected} but got {actual}"
            )
    finally:
        if service_proc is not None and service_proc.poll() is None:
            service_proc.terminate()
            try:
                service_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                service_proc.kill()
        if mock_proc.poll() is None:
            mock_proc.terminate()
            try:
                mock_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                mock_proc.kill()
        subprocess.run(["pkill", "-f", "/app/services/model_service.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
