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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import time
import uuid

import numpy as np
import pytest
import redis
import requests
from scipy.stats import ks_2samp, wasserstein_distance

BASELINE = [1.5, 2.1, 0.8, 1.1, 1.9]
INGEST_URL = "http://localhost:8080/ingest"
RESULTS_URL = "http://localhost:8080/results"


def expected_for(matrix):
    singular_values = np.linalg.svd(np.asarray(matrix, dtype=float), compute_uv=False)
    wd = float(wasserstein_distance(singular_values, BASELINE))
    pvalue = float(ks_2samp(singular_values, BASELINE).pvalue)
    return wd, pvalue, pvalue < 0.05


def find_result(data, matrix_id):
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get("id") == matrix_id:
                return item
    elif isinstance(data, dict):
        if data.get("id") == matrix_id:
            return data
        if matrix_id in data and isinstance(data[matrix_id], dict):
            return data[matrix_id]
    return None


def test_pipeline_end_to_end_and_worker():
    # Verify that the requested artifact is a Bash worker containing the required
    # Redis blocking-pop and authenticated webhook operations.
    worker_path = "/app/worker.sh"
    assert os.path.isfile(worker_path), "/app/worker.sh is missing or is not a regular file"
    with open(worker_path, "r", encoding="utf-8", errors="replace") as f:
        worker_text = f.read()
    assert worker_text.splitlines() and "bash" in worker_text.splitlines()[0].lower(), \
        "/app/worker.sh must be a Bash script"
    syntax = subprocess.run(["bash", "-n", worker_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax in worker.sh: {syntax.stderr}"
    lowered = worker_text.lower()
    assert "redis-cli" in lowered and "blpop" in lowered and "incoming_matrices" in worker_text, \
        "worker.sh must use redis-cli blpop on incoming_matrices"
    assert "curl" in lowered and "/report" in worker_text and "secret-ml-token" in worker_text, \
        "worker.sh must use curl to send an authenticated report"

    # Execute the submitted worker itself and ensure it remains a continuous process.
    worker_log = open("/tmp/verifier-worker.log", "ab", buffering=0)
    worker = subprocess.Popen(
        ["bash", worker_path],
        stdout=worker_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    time.sleep(1)
    assert worker.poll() is None, "worker.sh exited instead of continuously monitoring Redis"

    # Preserve the original fixed end-to-end case, and add unpredictable cases whose
    # expected answers are independently derived at verification time.
    rng = secrets.SystemRandom()
    cases = {
        "test_matrix_1": [[1.2, 0.5], [0.5, 1.8]],
        "random_ingest_" + uuid.uuid4().hex: [
            [round(rng.uniform(-4.0, 4.0), 7) for _ in range(4)] for _ in range(3)
        ],
        "random_ingest_" + uuid.uuid4().hex: [
            [round(rng.uniform(8.0, 25.0), 7) for _ in range(3)] for _ in range(5)
        ],
    }

    expected = {matrix_id: expected_for(matrix) for matrix_id, matrix in cases.items()}

    for matrix_id, matrix in cases.items():
        try:
            response = requests.post(
                INGEST_URL,
                json={"id": matrix_id, "matrix": matrix},
                timeout=5,
            )
        except requests.RequestException as exc:
            pytest.fail(f"Could not connect to Nginx ingest endpoint: {exc}")
        assert response.status_code == 200, \
            f"Failed to post to ingest API. Status: {response.status_code}, Body: {response.text}"

    # Push an unpredictable case directly into Redis. This cannot be satisfied by an
    # /ingest endpoint that computes or returns canned results; the running worker must
    # consume incoming_matrices and report it to the webhook service.
    direct_id = "direct_redis_" + uuid.uuid4().hex
    direct_matrix = [
        [round(rng.uniform(-30.0, 30.0), 7) for _ in range(4)] for _ in range(4)
    ]
    expected[direct_id] = expected_for(direct_matrix)
    try:
        redis_client = redis.Redis(host="localhost", port=6379, db=0)
        redis_client.ping()
        redis_client.rpush(
            "incoming_matrices",
            json.dumps({"id": direct_id, "matrix": direct_matrix}),
        )
    except Exception as exc:
        pytest.fail(f"Redis was unavailable for direct worker test: {exc}")

    # The webhook must enforce the required bearer token rather than accepting reports
    # from an unauthenticated shortcut.
    unauthorized_id = "unauthorized_" + uuid.uuid4().hex
    unauthorized = requests.post(
        "http://localhost:8002/report",
        json={"id": unauthorized_id},
        timeout=5,
    )
    assert unauthorized.status_code == 401, "Webhook /report did not enforce Authorization"

    pending = set(expected)
    results = {}
    deadline = time.time() + 35
    last_error = None
    while pending and time.time() < deadline:
        try:
            response = requests.get(RESULTS_URL, timeout=5)
            assert response.status_code == 200, \
                f"Results endpoint returned HTTP {response.status_code}"
            data = response.json()
            for matrix_id in list(pending):
                item = find_result(data, matrix_id)
                if item is not None:
                    results[matrix_id] = item
                    pending.remove(matrix_id)
        except (requests.RequestException, ValueError, AssertionError) as exc:
            last_error = exc
        if pending:
            time.sleep(1)

    assert not pending, \
        f"Did not find results for {sorted(pending)} at {RESULTS_URL}; last error: {last_error}"

    for matrix_id, result_data in results.items():
        assert result_data.get("id") == matrix_id, f"Result for {matrix_id} has the wrong id"
        assert "wasserstein_distance" in result_data, "Missing wasserstein_distance in result"
        assert "ks_pvalue" in result_data, "Missing ks_pvalue in result"
        assert "drift_detected" in result_data, "Missing drift_detected in result"

        actual_wd = result_data["wasserstein_distance"]
        actual_pvalue = result_data["ks_pvalue"]
        actual_drift = result_data["drift_detected"]
        assert isinstance(actual_wd, (int, float)) and not isinstance(actual_wd, bool)
        assert isinstance(actual_pvalue, (int, float)) and not isinstance(actual_pvalue, bool)
        assert math.isfinite(actual_wd) and math.isfinite(actual_pvalue)
        assert isinstance(actual_drift, bool)

        expected_wd, expected_pvalue, expected_drift = expected[matrix_id]
        assert np.isclose(actual_wd, expected_wd, atol=1e-3), \
            f"Expected wasserstein_distance ~ {expected_wd}, got {actual_wd} for {matrix_id}"
        assert np.isclose(actual_pvalue, expected_pvalue, atol=1e-3), \
            f"Expected ks_pvalue ~ {expected_pvalue}, got {actual_pvalue} for {matrix_id}"
        assert actual_drift == expected_drift, \
            f"Expected drift_detected={expected_drift}, got {actual_drift} for {matrix_id}"

    assert worker.poll() is None, "worker.sh stopped while processing matrices"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
