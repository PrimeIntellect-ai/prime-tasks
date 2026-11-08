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
import math
import random

import numpy as np
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

BASE_URL = "http://127.0.0.1:8123"


def load_data():
    data = {}
    with open("/app/customers.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = int(row["uid"])
            feat1 = float(row["feat1"])
            feat2 = float(row["feat2"])
            feat3 = float(row["feat3"])
            spend = float(row["spend"])
            data[uid] = {"feats": (feat1, feat2, feat3), "spend": spend}
    return data


def cosine_similarity(v1, v2):
    dot = sum(x * y for x, y in zip(v1, v2))
    norm1 = math.sqrt(sum(x * x for x in v1))
    norm2 = math.sqrt(sum(x * x for x in v2))
    if norm1 == 0 or norm2 == 0:
        return 0.0
    return dot / (norm1 * norm2)


def get_top_3_similar(data, target_uid):
    target_feats = data[target_uid]["feats"]
    sims = []
    for uid, info in data.items():
        if uid == target_uid:
            continue
        sim = cosine_similarity(target_feats, info["feats"])
        sims.append((uid, sim))
    sims.sort(key=lambda x: x[1], reverse=True)
    return [uid for uid, sim in sims[:3]]


@pytest.fixture(scope="module")
def dataset():
    return load_data()


@pytest.fixture(scope="module")
def expected_predictions(dataset):
    ordered_uids = list(dataset.keys())
    X = np.asarray([dataset[uid]["feats"] for uid in ordered_uids], dtype=float)
    y = np.asarray([dataset[uid]["spend"] for uid in ordered_uids], dtype=float)

    # GridSearchCV uses five non-shuffled folds and Ridge's R^2 score, then
    # refits the selected alpha on the entire dataset.
    search = GridSearchCV(
        Ridge(),
        {"alpha": [0.1, 1.0, 10.0]},
        cv=5,
        scoring=None,
        refit=True,
    )
    search.fit(X, y)
    predictions = search.best_estimator_.predict(X)
    return dict(zip(ordered_uids, predictions))


def shuffled_uids(dataset):
    uids = list(dataset.keys())
    random.SystemRandom().shuffle(uids)
    return uids


def test_similar_endpoint(dataset):
    """Test /similar exhaustively, in an order not known while the service is built."""
    for test_uid in shuffled_uids(dataset):
        expected_top_3 = get_top_3_similar(dataset, test_uid)

        try:
            response = requests.get(
                f"{BASE_URL}/similar", params={"uid": test_uid}, timeout=5
            )
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to /similar endpoint: {e}")

        assert response.status_code == 200, (
            f"Expected status 200, got {response.status_code}"
        )

        try:
            result = response.json()
        except ValueError:
            pytest.fail(f"Response from /similar is not valid JSON: {response.text}")

        assert isinstance(result, list), f"Expected a JSON array, got {type(result)}"
        assert len(result) == 3, (
            f"Expected exactly 3 similar UIDs, got {len(result)}"
        )
        assert result == expected_top_3, (
            f"For UID {test_uid}, expected {expected_top_3}, but got {result}"
        )


def test_predict_endpoint(dataset, expected_predictions):
    """Test /predict exhaustively against the required five-fold Ridge model."""
    for test_uid in shuffled_uids(dataset):
        try:
            response = requests.get(
                f"{BASE_URL}/predict", params={"uid": test_uid}, timeout=5
            )
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to /predict endpoint: {e}")

        assert response.status_code == 200, (
            f"Expected status 200, got {response.status_code}"
        )

        try:
            result = response.json()
        except ValueError:
            pytest.fail(f"Response from /predict is not valid JSON: {response.text}")

        assert isinstance(result, float) or isinstance(result, int), (
            f"Expected a JSON float, got {type(result)}"
        )
        assert math.isfinite(float(result)), f"Prediction for UID {test_uid} is not finite"

        # Retain the original generating-formula sanity assertion.
        feats = dataset[test_uid]["feats"]
        approx_true_spend = 2.5 * feats[0] - 1.2 * feats[1] + 0.5 * feats[2]
        assert abs(result - approx_true_spend) < 5.0, (
            f"Predicted spend {result} for UID {test_uid} is too far from "
            f"expected approx true spend {approx_true_spend}"
        )

        expected = float(expected_predictions[test_uid])
        assert math.isclose(float(result), expected, rel_tol=1e-6, abs_tol=1e-4), (
            f"For UID {test_uid}, expected five-fold-selected Ridge prediction "
            f"{expected}, but got {result}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
