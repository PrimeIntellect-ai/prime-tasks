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
import io
import math
import os
import secrets

import pandas as pd
import pytest
import requests
from scipy import stats
from sklearn.datasets import make_classification
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer EXP-9942-X"}
BAD_AUTH_HEADER = {"Authorization": "Bearer WRONG-TOKEN"}
DATASET_PATH = "/app/dataset.csv"

# Snapshot the dataset before any endpoint is invoked, so a request cannot change
# the data against which its response is checked.
with open(DATASET_PATH, "rb") as f:
    ORIGINAL_DATASET = f.read()
ORIGINAL_MODE = os.stat(DATASET_PATH).st_mode & 0o777


def compute_expected(dataset_bytes):
    df = pd.read_csv(io.BytesIO(dataset_bytes))
    df = df.dropna()
    df = df[df["target"].isin([0, 1])]

    X = df.drop(columns=["target"])
    y = df["target"]

    clf = RandomForestClassifier(random_state=1042)
    scores = cross_val_score(clf, X, y, cv=10)
    mean_acc = scores.mean()

    t_stat, p_val_2sided = stats.ttest_1samp(scores, 0.65)
    if t_stat > 0:
        p_val = p_val_2sided / 2
    else:
        p_val = 1 - (p_val_2sided / 2)

    reproducible = bool(p_val < 0.05 and mean_acc > 0.65)
    return mean_acc, p_val, reproducible


def assert_reproducibility_response(resp, expected):
    assert resp.status_code == 200, (
        f"Expected 200 OK for /test-reproducibility, got {resp.status_code}. "
        f"Response: {resp.text}"
    )

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(
            f"Response from /test-reproducibility was not valid JSON. Response: {resp.text}"
        )

    assert "mean_accuracy" in data, "Missing 'mean_accuracy' in response"
    assert "p_value" in data, "Missing 'p_value' in response"
    assert "reproducible" in data, "Missing 'reproducible' in response"

    mean_acc, p_val, reproducible = expected
    assert math.isclose(float(data["mean_accuracy"]), mean_acc, rel_tol=1e-3), (
        f"Expected mean_accuracy ~{mean_acc}, got {data['mean_accuracy']}"
    )
    assert math.isclose(float(data["p_value"]), p_val, rel_tol=1e-3), (
        f"Expected p_value ~{p_val}, got {data['p_value']}"
    )
    assert bool(data["reproducible"]) == reproducible, (
        f"Expected reproducible={reproducible}, got {data['reproducible']}"
    )


def restore_original_dataset():
    with open(DATASET_PATH, "wb") as f:
        f.write(ORIGINAL_DATASET)
    os.chmod(DATASET_PATH, ORIGINAL_MODE)


def test_metadata_endpoint_correct_auth():
    try:
        resp = requests.get(f"{BASE_URL}/metadata", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the API on 127.0.0.1:8080")

    assert resp.status_code == 200, f"Expected 200 OK for /metadata, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response from /metadata was not valid JSON. Response: {resp.text}")

    assert "seed" in data, "Missing 'seed' in metadata response"
    assert "alpha" in data, "Missing 'alpha' in metadata response"
    assert "baseline" in data, "Missing 'baseline' in metadata response"

    assert int(data["seed"]) == 1042, f"Expected seed 1042, got {data['seed']}"
    assert math.isclose(float(data["alpha"]), 0.05, rel_tol=1e-5), f"Expected alpha 0.05, got {data['alpha']}"
    assert math.isclose(float(data["baseline"]), 0.65, rel_tol=1e-5), f"Expected baseline 0.65, got {data['baseline']}"


def test_reproducibility_endpoint_correct_auth():
    # Derive the answer before making the request. The endpoint cannot pass by
    # replacing the world-writable dataset during the request.
    expected = compute_expected(ORIGINAL_DATASET)
    try:
        try:
            resp = requests.get(
                f"{BASE_URL}/test-reproducibility",
                headers=AUTH_HEADER,
                timeout=15,
            )
        except requests.exceptions.ConnectionError:
            pytest.fail("Could not connect to the API on 127.0.0.1:8080")
        assert_reproducibility_response(resp, expected)
    finally:
        restore_original_dataset()


def test_reproducibility_endpoint_runs_pipeline_dynamically():
    # Create an unpredictable valid replacement dataset, including rows that
    # exercise both required cleaning rules. A precomputed constant response or
    # a model loaded only at server startup will not match it.
    random_state = secrets.randbelow(2**31 - 1)
    X, y = make_classification(
        n_samples=420,
        n_features=5,
        n_informative=4,
        n_redundant=0,
        n_clusters_per_class=1,
        class_sep=secrets.choice([0.45, 0.7, 1.1, 1.6]),
        flip_y=0.08,
        random_state=random_state,
    )
    df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(5)])
    df["target"] = y
    df.loc[3, "feature_2"] = float("nan")
    df.loc[7, "target"] = 2

    buffer = io.StringIO()
    df.to_csv(buffer, index=False)
    replacement = buffer.getvalue().encode("utf-8")
    expected = compute_expected(replacement)

    try:
        with open(DATASET_PATH, "wb") as f:
            f.write(replacement)
        os.chmod(DATASET_PATH, 0o666)

        resp = requests.get(
            f"{BASE_URL}/test-reproducibility?verification_nonce={secrets.token_hex(16)}",
            headers=AUTH_HEADER,
            timeout=15,
        )
        assert_reproducibility_response(resp, expected)
    finally:
        restore_original_dataset()


def test_auth_failure():
    try:
        resp = requests.get(f"{BASE_URL}/metadata", headers=BAD_AUTH_HEADER, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the API on 127.0.0.1:8080")

    assert resp.status_code == 401, f"Expected 401 Unauthorized for /metadata with wrong token, got {resp.status_code}"

    resp2 = requests.get(f"{BASE_URL}/test-reproducibility", headers=BAD_AUTH_HEADER, timeout=15)
    assert resp2.status_code == 401, f"Expected 401 Unauthorized for /test-reproducibility with wrong token, got {resp2.status_code}"

    resp3 = requests.get(f"{BASE_URL}/metadata", timeout=5)
    assert resp3.status_code == 401, f"Expected 401 Unauthorized for /metadata with missing token, got {resp3.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
