#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import pytest
import requests
import numpy as np
from scipy.stats import pearsonr
import csv
import json
import math

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer LAB_SECURE_TOKEN_99"}

@pytest.fixture(scope="module")
def truth_values():
    try:
        import labschema
    except ImportError:
        pytest.fail("labschema package is not installed or cannot be imported.")

    clinical = {}
    with open("/home/user/data/clinical.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                row_dict = {
                    "patient_id": row["patient_id"],
                    "age": int(row["age"]),
                    "recovery_time": float(row["recovery_time"])
                }
                labschema.validate_clinical(row_dict)
                clinical[row["patient_id"]] = row_dict
            except Exception:
                continue

    biomarkers = {}
    with open("/home/user/data/biomarkers.json", "r") as f:
        data = json.load(f)
        for item in data:
            try:
                labschema.validate_biomarkers(item)
                biomarkers[item["patient_id"]] = item
            except Exception:
                continue

    joined = []
    for pid in clinical:
        if pid in biomarkers:
            joined.append((clinical[pid], biomarkers[pid]))

    joined.sort(key=lambda x: x[0]["patient_id"])

    X = []
    y = []
    for c, b in joined:
        y.append(c["recovery_time"])
        X.append([b[f"marker_{i}"] for i in range(1, 11)])

    X = np.array(X)
    y = np.array(y)

    X_mean = np.mean(X, axis=0)
    X_std = np.std(X, axis=0, ddof=0)
    X_scaled = (X - X_mean) / X_std

    U, S, Vt = np.linalg.svd(X_scaled, full_matrices=False)
    explained_variance_ratio = (S ** 2) / np.sum(S ** 2)

    PC1 = U[:, 0] * S[0]
    corr, pval = pearsonr(PC1, y)

    return {
        "explained_variance_ratio": explained_variance_ratio[:2].tolist(),
        "pc1_recovery_corr": corr,
        "p_value": pval
    }

def test_api_auth_required():
    try:
        response = requests.get(f"{BASE_URL}/api/pca", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {BASE_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized when no auth header is provided, got {response.status_code}"

def test_api_pca_endpoint(truth_values):
    try:
        response = requests.get(f"{BASE_URL}/api/pca", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    data = response.json()
    assert "explained_variance_ratio" in data, "Response missing 'explained_variance_ratio' key"

    agent_evr = data["explained_variance_ratio"]
    truth_evr = truth_values["explained_variance_ratio"]

    assert len(agent_evr) == 2, f"Expected 2 variance ratios, got {len(agent_evr)}"
    for a, t in zip(agent_evr, truth_evr):
        assert math.isclose(a, t, abs_tol=1e-4), f"Explained variance ratio mismatch: expected {t}, got {a}"

def test_api_stats_endpoint(truth_values):
    try:
        response = requests.get(f"{BASE_URL}/api/stats", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    data = response.json()
    assert "pc1_recovery_corr" in data, "Response missing 'pc1_recovery_corr' key"
    assert "p_value" in data, "Response missing 'p_value' key"

    agent_corr = data["pc1_recovery_corr"]
    truth_corr = truth_values["pc1_recovery_corr"]

    # PC1 sign is arbitrary, so correlation can be positive or negative
    assert math.isclose(abs(agent_corr), abs(truth_corr), abs_tol=1e-4), f"Correlation mismatch: expected {truth_corr} (or its negative), got {agent_corr}"

    agent_pval = data["p_value"]
    truth_pval = truth_values["p_value"]
    assert math.isclose(agent_pval, truth_pval, abs_tol=1e-4), f"P-value mismatch: expected {truth_pval}, got {agent_pval}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
