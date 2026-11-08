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
import csv
import json
import math
import os
import pickle
import random
import re
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/predict"
VALID_TOKEN = "Bearer etl-pipeline-secret-2024"
HEADERS = {"Authorization": VALID_TOKEN}


def project_files(suffixes):
    roots = [Path(p) for p in ("/home/user", "/app", "/workspace", "/root") if Path(p).exists()]
    excluded = {".git", ".venv", "venv", "site-packages", "node_modules", "__pycache__", ".cache"}
    found = []
    for root in roots:
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded]
            for name in files:
                path = Path(current) / name
                if path == Path("/app/sensor_simulator"):
                    continue
                if path.suffix.lower() in suffixes:
                    found.append(path)
    return found


def load_sensor_rows(path):
    if path.stat().st_size > 50 * 1024 * 1024:
        return []
    rows = []
    suffix = path.suffix.lower()
    try:
        if suffix == ".csv":
            with path.open("r", encoding="utf-8", errors="replace", newline="") as fh:
                rows = list(csv.DictReader(fh))
        elif suffix in {".jsonl", ".ndjson"}:
            with path.open("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        item = json.loads(line)
                        if isinstance(item, dict):
                            rows.append(item)
        elif suffix == ".json":
            with path.open("r", encoding="utf-8", errors="replace") as fh:
                value = json.load(fh)
            if isinstance(value, list):
                rows = [x for x in value if isinstance(x, dict)]
            elif isinstance(value, dict):
                for key in ("readings", "records", "data", "samples"):
                    if isinstance(value.get(key), list):
                        rows = [x for x in value[key] if isinstance(x, dict)]
                        break
        elif suffix in {".parquet", ".feather"}:
            import pandas as pd
            frame = pd.read_parquet(path) if suffix == ".parquet" else pd.read_feather(path)
            rows = frame.to_dict("records")
    except Exception:
        return []

    valid = []
    for row in rows:
        try:
            values = tuple(float(row[k]) for k in ("v1", "v2", "v3"))
            if all(math.isfinite(x) for x in values):
                valid.append(values)
        except (KeyError, TypeError, ValueError):
            continue
    return valid


def fitted_estimator(value):
    if isinstance(value, dict):
        return any(fitted_estimator(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(fitted_estimator(v) for v in value)
    if not callable(getattr(value, "predict", None)):
        return False
    try:
        from sklearn.utils.validation import check_is_fitted
        check_is_fitted(value)
        return True
    except Exception:
        fitted_names = [name for name in vars(value) if name.endswith("_") and not name.startswith("__")]
        return bool(fitted_names)


def test_pipeline_artifacts_exist_and_are_reproducible():
    python_files = project_files({".py"})
    assert python_files, "No Python ETL, training, or serving implementation was found"

    sources = []
    for path in python_files:
        try:
            if path.stat().st_size <= 2 * 1024 * 1024:
                sources.append((path, path.read_text(encoding="utf-8", errors="replace").lower()))
        except OSError:
            pass
    combined = "\n".join(text for _, text in sources)

    collectors = [path for path, text in sources if "sensor_simulator" in text and any(x in text for x in ("subprocess", "popen", "os.popen"))]
    trainers = [path for path, text in sources if re.search(r"\.fit\s*\(", text)]
    servers = [path for path, text in sources if "/predict" in text and "etl-pipeline-secret-2024" in text]
    assert collectors, "No Python ETL collector that executes sensor_simulator was found"
    assert trainers, "No reproducible Python model-training code using fit(...) was found"
    assert servers, "No Python model-serving implementation for the authenticated /predict endpoint was found"
    assert any(x in combined for x in ("pickle.dump", "joblib.dump", ".save(")), "Training code does not persist a trained model"

    data_files = project_files({".csv", ".json", ".jsonl", ".ndjson", ".parquet", ".feather"})
    datasets = [(path, load_sensor_rows(path)) for path in data_files]
    datasets = [(path, rows) for path, rows in datasets if len(rows) >= 150]
    assert datasets, "No collected sensor dataset with at least 150 valid feature rows was found"
    _, rows = max(datasets, key=lambda item: len(item[1]))
    assert len(set(rows)) >= 100, "Collected sensor data lacks sufficient variation"
    assert any(v1 >= 8.0 and v2 >= 8.0 and v3 < 2.0 for v1, v2, v3 in rows), "Collected data contains no anomalous-regime samples"
    assert any(v3 >= 2.0 for _, _, v3 in rows), "Collected data contains no normal-regime samples"

    model_files = project_files({".pkl", ".pickle", ".joblib", ".sav"})
    valid_models = []
    for path in model_files:
        if path.stat().st_size <= 0 or path.stat().st_size > 200 * 1024 * 1024:
            continue
        try:
            try:
                import joblib
                model = joblib.load(path)
            except Exception:
                with path.open("rb") as fh:
                    model = pickle.load(fh)
            if fitted_estimator(model):
                valid_models.append(path)
        except Exception:
            continue
    assert valid_models, "No loadable, fitted prediction model artifact was found"


def test_auth_missing_token():
    payload = {"sensor_id": 1, "v1": 0.0, "v2": 0.0, "v3": 0.0}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:8080")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"


def test_auth_invalid_token():
    payload = {"sensor_id": 1, "v1": 0.0, "v2": 0.0, "v3": 0.0}
    response = requests.post(URL, json=payload, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}"


def test_predict_anomaly_true():
    payload = {"sensor_id": 42, "v1": 10.5, "v2": 6.1, "v3": 1.2}
    response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    data = response.json()
    assert "anomaly" in data, "Response JSON missing 'anomaly' key"
    assert data["anomaly"] is True, f"Expected anomaly=True for payload {payload}, got {data['anomaly']}"


def test_predict_anomaly_false():
    payload = {"sensor_id": 42, "v1": 5.0, "v2": 5.0, "v3": 5.0}
    response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    data = response.json()
    assert "anomaly" in data, "Response JSON missing 'anomaly' key"
    assert data["anomaly"] is False, f"Expected anomaly=False for payload {payload}, got {data['anomaly']}"


def test_predict_edge_cases():
    payload1 = {"sensor_id": 10, "v1": 10.0, "v2": 6.0, "v3": 2.5}
    resp1 = requests.post(URL, json=payload1, headers=HEADERS, timeout=5)
    assert resp1.json().get("anomaly") is False, f"Expected False for {payload1}"

    payload2 = {"sensor_id": 11, "v1": 7.0, "v2": 7.0, "v3": 1.0}
    resp2 = requests.post(URL, json=payload2, headers=HEADERS, timeout=5)
    assert resp2.json().get("anomaly") is False, f"Expected False for {payload2}"

    payload3 = {"sensor_id": 12, "v1": 8.0, "v2": 7.5, "v3": 1.9}
    resp3 = requests.post(URL, json=payload3, headers=HEADERS, timeout=5)
    assert resp3.json().get("anomaly") is True, f"Expected True for {payload3}"


def test_randomized_predictions_from_sensor_distribution():
    rng = random.SystemRandom()
    cases = []
    for i in range(30):
        cases.append(({"sensor_id": 100000 + i, "v1": rng.uniform(8.1, 12.9), "v2": rng.uniform(8.1, 12.9), "v3": rng.uniform(0.05, 1.85)}, True))
    for i in range(30):
        cases.append(({"sensor_id": 200000 + i, "v1": rng.uniform(0.05, 9.95), "v2": rng.uniform(0.05, 9.95), "v3": rng.uniform(2.05, 9.95)}, False))
    rng.shuffle(cases)

    for payload, expected in cases:
        response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK for {payload}, got {response.status_code}"
        data = response.json()
        assert "anomaly" in data, "Response JSON missing 'anomaly' key"
        assert data["anomaly"] is expected, f"Unexpected prediction for generated sensor reading {payload}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
