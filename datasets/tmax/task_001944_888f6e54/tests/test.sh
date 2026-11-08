#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

import joblib
import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV

HOME = "/home/user"
COUNTER = "/tmp/benchmark_requests.jsonl"


def expected_artifacts():
    raw = pd.read_csv(f"{HOME}/raw_sensors.csv", parse_dates=["timestamp"])
    expected = raw.sort_values(["sensor_id", "timestamp"], ascending=True).copy()
    features = ["temperature", "vibration", "pressure"]
    expected[features] = (
        expected.groupby("sensor_id", sort=False)[features]
        .rolling(window=3)
        .mean()
        .reset_index(level=0, drop=True)
    )
    expected = expected.dropna().reset_index(drop=True)

    search = GridSearchCV(
        RandomForestClassifier(random_state=42),
        {"n_estimators": [10, 50], "max_depth": [3, 5]},
        cv=3,
    )
    search.fit(expected[features], expected["status"])
    return expected, features, search


def stop_listener(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def request_prediction(payload, timeout=5):
    req = urllib.request.Request(
        "http://127.0.0.1:8000/predict",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            try:
                result = json.loads(response.read().decode("utf-8"))
            except json.JSONDecodeError:
                pytest.fail("API response is not valid JSON.")
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to the API at http://127.0.0.1:8000/predict: {exc}")

    assert "status" in result, "Response JSON is missing 'status' key."
    assert isinstance(result["status"], int) and not isinstance(result["status"], bool), (
        "The 'status' value in response must be an integer."
    )
    assert result["status"] in (0, 1), "The API status must be class 0 or 1."
    return result["status"]


def launch_instrumented_agent_app():
    assert os.path.isfile(f"{HOME}/app.py"), "FastAPI application /home/user/app.py is missing."
    stop_listener(8000)
    with open("/tmp/verifier_server.py", "w") as f:
        f.write(r'''import json
import sys
sys.path.insert(0, "/home/user")
import app as agent_app

COUNTER = "/tmp/benchmark_requests.jsonl"

class CountingASGI:
    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http":
            return await self.inner(scope, receive, send)

        messages = []
        body = b""
        while True:
            message = await receive()
            messages.append(message)
            if message.get("type") == "http.request":
                body += message.get("body", b"")
                if not message.get("more_body", False):
                    break
            else:
                break

        if scope.get("method") == "POST" and scope.get("path") == "/predict":
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception:
                payload = None
            with open(COUNTER, "a") as out:
                out.write(json.dumps(payload) + "\n")

        index = 0
        async def replay():
            nonlocal index
            if index < len(messages):
                message = messages[index]
                index += 1
                return message
            return {"type": "http.disconnect"}

        return await self.inner(scope, replay, send)

app = CountingASGI(agent_app.app)
''')

    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "verifier_server:app", "--host", "127.0.0.1", "--port", "8000"],
        cwd="/tmp",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("The FastAPI application failed to start under uvicorn.")
        try:
            request_prediction({"temperature": 0.5, "vibration": 0.5, "pressure": 0.5}, timeout=1)
            return proc
        except BaseException:
            time.sleep(0.2)
    pytest.fail("The FastAPI application did not become ready on port 8000.")


def test_complete_pipeline_and_service():
    processed_path = f"{HOME}/processed_sensors.csv"
    assert os.path.isfile(processed_path), f"Processed dataset is missing: {processed_path}"
    with open(processed_path) as f:
        lines = f.readlines()
    assert len(lines) == 4961, f"Expected 4961 lines in {processed_path}, but found {len(lines)}."

    expected, features, search = expected_artifacts()
    actual = pd.read_csv(processed_path, parse_dates=["timestamp"])
    assert list(actual.columns) == list(expected.columns), "Processed CSV columns are incorrect."
    assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=1e-10,
    )

    params_path = f"{HOME}/best_params.json"
    assert os.path.isfile(params_path), f"Best parameters file is missing: {params_path}"
    try:
        with open(params_path) as f:
            params = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {params_path} is not valid JSON.")
    assert "max_depth" in params, "Key 'max_depth' is missing from best_params.json."
    assert "n_estimators" in params, "Key 'n_estimators' is missing from best_params.json."
    assert params == search.best_params_, "best_params.json does not contain GridSearchCV's best parameters."

    model_path = f"{HOME}/best_model.joblib"
    assert os.path.isfile(model_path), f"Best model is missing: {model_path}"
    model = joblib.load(model_path)
    assert isinstance(model, RandomForestClassifier), "best_model.joblib is not a RandomForestClassifier."
    assert model.random_state == 42, "RandomForestClassifier random_state must be 42."
    assert model.n_estimators == params["n_estimators"]
    assert model.max_depth == params["max_depth"]
    assert hasattr(model, "estimators_") and len(model.estimators_) == model.n_estimators, "Model is not fitted."
    assert list(getattr(model, "feature_names_in_", [])) == features, "Model was not fitted using only the three rolling-mean features."

    X = expected[features]
    reference = search.best_estimator_
    np.testing.assert_array_equal(model.predict(X), reference.predict(X))
    np.testing.assert_allclose(model.predict_proba(X), reference.predict_proba(X), rtol=1e-12, atol=1e-12)

    status_path = f"{HOME}/benchmark_status.txt"
    assert os.path.isfile(status_path), f"Benchmark status file is missing: {status_path}"
    with open(status_path) as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected benchmark_status.txt to contain 'SUCCESS', but got '{content}'."
    assert os.path.isfile(f"{HOME}/benchmark.py"), "Benchmark script /home/user/benchmark.py is missing."

    launch_instrumented_agent_app()

    probes = [
        {"temperature": 0.5, "vibration": 0.5, "pressure": 0.5},
        {"temperature": 50.0, "vibration": 5.0, "pressure": 100.0},
        {"temperature": 70.0, "vibration": 9.0, "pressure": 115.0},
        {"temperature": 42.5, "vibration": 7.5, "pressure": 87.0},
    ]
    expected_predictions = model.predict(pd.DataFrame(probes, columns=features)).astype(int).tolist()
    actual_predictions = [request_prediction(payload) for payload in probes]
    assert actual_predictions == expected_predictions, "The API predictions do not match best_model.joblib."

    open(COUNTER, "w").close()
    os.unlink(status_path)
    run = subprocess.run(
        [sys.executable, f"{HOME}/benchmark.py"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert run.returncode == 0, f"benchmark.py failed:\n{run.stdout}\n{run.stderr}"
    assert os.path.isfile(status_path), "benchmark.py did not create benchmark_status.txt."
    with open(status_path) as f:
        assert f.read().strip() == "SUCCESS", "benchmark.py did not write SUCCESS after completing."

    with open(COUNTER) as f:
        requests_seen = [json.loads(line) for line in f if line.strip()]
    dummy = {"temperature": 0.5, "vibration": 0.5, "pressure": 0.5}
    assert len(requests_seen) == 100, f"benchmark.py sent {len(requests_seen)} POST requests instead of 100."
    assert all(payload == dummy for payload in requests_seen), "benchmark.py did not use the required dummy payload for every request."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
