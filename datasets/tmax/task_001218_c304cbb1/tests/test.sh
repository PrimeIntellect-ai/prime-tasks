#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import time
from pathlib import Path

import pandas as pd
import pytest
import requests
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler

URL = "http://127.0.0.1:5000/predict"


def build_reference_model():
    csv_path = "/app/raw_housing_data.csv"
    assert os.path.exists(csv_path), f"Raw dataset missing at {csv_path}"
    df = pd.read_csv(csv_path)

    train_size = int(len(df) * 0.8)
    train_df = df.iloc[:train_size].copy()
    train_df["Area_t"] = train_df["Area"] * 0.95
    train_df["Age_t"] = (train_df["Age"] - 2) * 1.1

    scaler = StandardScaler()
    train_df["Income_t"] = scaler.fit_transform(train_df[["Income"]])

    model = LinearRegression()
    model.fit(train_df[["Area_t", "Age_t", "Income_t"]], train_df["Price"])
    return model, scaler


def expected_prediction(model, scaler, payload):
    row = [[
        payload["Area"] * 0.95,
        (payload["Age"] - 2) * 1.1,
        scaler.transform([[payload["Income"]]])[0][0],
    ]]
    return float(model.predict(row)[0])


def post_prediction(payload, retries=5):
    response = None
    for _ in range(retries):
        try:
            response = requests.post(URL, json=payload, timeout=5)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            time.sleep(1)

    assert response is not None, f"API is not reachable at {URL}"
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"API did not return valid JSON. Response text: {response.text}")

    assert "predicted_price" in data, (
        f"Response JSON missing 'predicted_price' key. Got: {data}"
    )
    actual = data["predicted_price"]
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
        "predicted_price must be a number"
    )
    assert math.isfinite(actual), "predicted_price must be finite"
    return float(actual)


def test_api_running_and_predicts_correctly():
    model, scaler = build_reference_model()

    # Preserve the original fixed-request assertion.
    payload = {"Area": 2000, "Age": 5, "Income": 80000}
    expected = expected_prediction(model, scaler, payload)
    actual = post_prediction(payload)
    rel_error = abs(actual - expected) / abs(expected)
    assert rel_error < 0.05, (
        f"Predicted price {actual} is not close enough to expected {expected} "
        f"(relative error {rel_error:.4f} >= 0.05). Check ETL logic and split."
    )

    # Exercise general prediction behavior on values selected only after the
    # agent has finished. This prevents a fixed response for the public example.
    rng = random.SystemRandom()
    payloads = [
        {
            "Area": rng.uniform(1400, 4400),
            "Age": rng.uniform(5, 70),
            "Income": rng.uniform(40000, 180000),
        }
        for _ in range(8)
    ]

    predictions = []
    for dynamic_payload in payloads:
        dynamic_expected = expected_prediction(model, scaler, dynamic_payload)
        dynamic_actual = post_prediction(dynamic_payload)
        predictions.append(dynamic_actual)
        dynamic_rel_error = abs(dynamic_actual - dynamic_expected) / abs(dynamic_expected)
        assert dynamic_rel_error < 0.04, (
            f"Prediction {dynamic_actual} for {dynamic_payload} is not close to "
            f"the trained-pipeline result {dynamic_expected} "
            f"(relative error {dynamic_rel_error:.4f} >= 0.04)"
        )

    assert max(predictions) - min(predictions) > 10000, (
        "API predictions do not vary meaningfully across distinct inputs"
    )


def test_persisted_model_and_etl_state_exist():
    excluded = {
        "/app/raw_housing_data.csv",
        "/app/scaling_rules.png",
        "/app/api.pid",
    }
    keywords = (
        "model", "pipeline", "scaler", "etl", "state", "preprocess",
        "params", "coefficients",
    )
    serialized_extensions = {
        ".pkl", ".pickle", ".joblib", ".json", ".npz", ".npy",
        ".sav", ".bin", ".onnx", ".pt",
    }
    source_extensions = {
        ".py", ".pyc", ".js", ".ts", ".sh", ".html", ".css",
        ".log", ".csv", ".png", ".jpg", ".jpeg",
    }

    candidates = []
    for path in Path("/app").rglob("*"):
        if not path.is_file() or str(path) in excluded:
            continue
        if "__pycache__" in path.parts or path.suffix.lower() in source_extensions:
            continue
        name = path.name.lower()
        if path.suffix.lower() in serialized_extensions or any(k in name for k in keywords):
            candidates.append(path)

    assert candidates, (
        "No persisted model parameters or ETL/scaler state were found under /app"
    )
    total_size = sum(path.stat().st_size for path in candidates)
    assert total_size >= 64, (
        f"Persisted model/ETL artifacts appear empty or incomplete: {candidates}"
    )


def process_tree(root_pid):
    found = {root_pid}
    changed = True
    while changed:
        changed = False
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                fields = (entry / "stat").read_text().split()
                pid, ppid = int(fields[0]), int(fields[3])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in found and pid not in found:
                found.add(pid)
                changed = True
    return found


def listening_socket_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_address, state, inode = fields[1], fields[3], fields[9]
            try:
                port = int(local_address.rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port == 5000 and state == "0A":
                inodes.add(inode)
    return inodes


def test_pid_file_exists():
    pid_file = "/app/api.pid"
    assert os.path.exists(pid_file), f"PID file is missing at {pid_file}"
    with open(pid_file, "r") as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"PID file contains invalid PID: {pid_text}"

    pid = int(pid_text)
    assert pid > 1 and Path(f"/proc/{pid}").exists(), (
        f"PID file points to a process that is not running: {pid}"
    )

    listener_inodes = listening_socket_inodes()
    assert listener_inodes, "No process is listening on TCP port 5000"

    owns_listener = False
    for process_pid in process_tree(pid):
        fd_dir = Path(f"/proc/{process_pid}/fd")
        try:
            descriptors = list(fd_dir.iterdir())
        except OSError:
            continue
        for descriptor in descriptors:
            try:
                target = os.readlink(descriptor)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in listener_inodes:
                owns_listener = True
                break
        if owns_listener:
            break

    assert owns_listener, (
        f"PID {pid} (or its child processes) does not own the API listener on port 5000"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
