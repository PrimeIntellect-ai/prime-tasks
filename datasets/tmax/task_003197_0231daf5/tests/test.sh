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
import csv
import subprocess
import sys
import time
import requests
import numpy as np
import pandas as pd
import joblib
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
import pytest

RAW_DATA_PATH = "/app/data/raw_features.csv"
PROCESSED_DATA_PATH = "/home/user/processed_features.csv"
MODEL_PATH = "/home/user/pca_model.pkl"
LOG_PATH = "/home/user/server.log"
BASE_URL = "http://127.0.0.1:8080"
TOKEN = "secret_ml_token_99X"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def reference():
    raw = pd.read_csv(RAW_DATA_PATH)
    assert list(raw.columns) == [f"f_{i}" for i in range(50)]
    scaler = StandardScaler()
    scaled = scaler.fit_transform(raw.to_numpy())
    pca = PCA(n_components=5)
    transformed = pca.fit_transform(scaled)
    return raw.to_numpy(), scaler, pca, transformed


def test_files_exist():
    assert os.path.isfile("/home/user/etl_pipeline.py"), "ETL script missing at /home/user/etl_pipeline.py"
    assert os.path.isfile("/home/user/serve_features.py"), "Serve script missing at /home/user/serve_features.py"
    assert os.path.isfile(MODEL_PATH), f"PCA model missing at {MODEL_PATH}"
    assert os.path.isfile(PROCESSED_DATA_PATH), f"Processed features missing at {PROCESSED_DATA_PATH}"
    assert os.path.isfile(LOG_PATH), f"Server log missing at {LOG_PATH}"


def test_makefile_fixed_and_package_installed():
    makefile = "/app/feature_server_pkg-1.2.0/Makefile"
    assert os.path.isfile(makefile), "Vendored Makefile is missing"
    text = open(makefile).read()
    assert "python3.5" not in text, "Makefile still hardcodes the incorrect Python version"
    subprocess.run(["make", "-C", "/app/feature_server_pkg-1.2.0", "install"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    code = "import feature_server_pkg; assert hasattr(feature_server_pkg, 'AppServer')"
    subprocess.run([sys.executable, "-c", code], check=True, timeout=20)


def test_etl_is_reproducible_and_outputs_correct_values():
    # Remove generated artifacts and require the submitted ETL program to recreate them.
    for path in (MODEL_PATH, PROCESSED_DATA_PATH):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([sys.executable, "/home/user/etl_pipeline.py"], check=True,
                   cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                   text=True, timeout=120)
    assert os.path.isfile(MODEL_PATH), "ETL did not create pca_model.pkl"
    assert os.path.isfile(PROCESSED_DATA_PATH), "ETL did not create processed_features.csv"

    actual = pd.read_csv(PROCESSED_DATA_PATH)
    assert list(actual.columns) == ["pc_1", "pc_2", "pc_3", "pc_4", "pc_5"]
    assert actual.shape == (100, 5)
    assert np.isfinite(actual.to_numpy()).all()
    _, _, _, expected = reference()
    # PCA component signs are arbitrary; align each submitted output column before comparison.
    aligned = actual.to_numpy().copy()
    for j in range(5):
        if np.dot(aligned[:, j], expected[:, j]) < 0:
            aligned[:, j] *= -1
    np.testing.assert_allclose(aligned, expected, rtol=1e-5, atol=1e-5,
                               err_msg="processed_features.csv does not contain the required standardized PCA transform")

    model = joblib.load(MODEL_PATH)
    assert hasattr(model, "transform"), "Saved model does not expose transform"


def test_processed_features_format():
    with open(PROCESSED_DATA_PATH, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Processed features file is empty")
        assert header == ["pc_1", "pc_2", "pc_3", "pc_4", "pc_5"], f"Incorrect header in processed features: {header}"
        rows = list(reader)
        assert len(rows) > 0, "Processed features file has no data rows"
        assert len(rows[0]) == 5, f"Processed features should have exactly 5 columns, got {len(rows[0])}"
        with open(RAW_DATA_PATH, 'r') as rf:
            raw_rows = list(csv.reader(rf))
            assert len(rows) == len(raw_rows) - 1, "Processed features row count does not match raw features row count"


def test_health_endpoint():
    try:
        resp_unauth = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {BASE_URL}: {e}")
    assert resp_unauth.status_code == 401
    assert requests.get(f"{BASE_URL}/health", headers={"Authorization": "Bearer wrong"}, timeout=5).status_code == 401
    resp_auth = requests.get(f"{BASE_URL}/health", headers=HEADERS, timeout=5)
    assert resp_auth.status_code == 200
    assert resp_auth.json() == {"status": "ok"}


def test_transform_endpoint_multiple_derived_inputs():
    raw_data, scaler, pca, _ = reference()
    # Values are derived from source data and are deliberately varied, preventing a fixed response.
    inputs = [
        np.zeros(50),
        raw_data[7],
        0.37 * raw_data[13] - 0.81 * raw_data[62] + np.linspace(-0.4, 0.6, 50),
    ]
    resp_unauth = requests.post(f"{BASE_URL}/transform", json={"features": inputs[0].tolist()}, timeout=5)
    assert resp_unauth.status_code == 401
    for point in inputs:
        resp = requests.post(f"{BASE_URL}/transform", headers=HEADERS,
                             json={"features": point.tolist()}, timeout=5)
        assert resp.status_code == 200, resp.text
        result = resp.json()
        assert "reduced_features" in result
        reduced = np.asarray(result["reduced_features"], dtype=float)
        assert reduced.shape == (5,)
        expected = pca.transform(scaler.transform([point]))[0]
        np.testing.assert_allclose(reduced, expected, rtol=1e-4, atol=1e-4,
                                   err_msg="API does not apply the fitted scaler and PCA")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
