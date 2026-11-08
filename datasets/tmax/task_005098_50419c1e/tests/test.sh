#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/sanitiser.py"


def get_redis_ingest_count():
    try:
        result = subprocess.run(
            ["redis-cli", "GET", "ingest_count"],
            capture_output=True,
            text=True,
            check=True,
        )
        val = result.stdout.strip()
        if val == "(nil)" or not val:
            return 0
        return int(val.replace('"', ''))
    except Exception:
        return 0


def make_full_rank_matrix(rng):
    while True:
        X = rng.normal(size=(10, 5))
        if np.linalg.det(X.T @ X) >= 1.0:
            return X


def make_clean_case(rng):
    while True:
        X = make_full_rank_matrix(rng)
        y = rng.normal(size=10)
        correlations = [abs(np.corrcoef(y, X[:, i])[0, 1]) for i in range(X.shape[1])]
        if max(correlations) < 0.95:
            return {"X": X.tolist(), "y": y.tolist()}


def make_collinear_case(rng):
    X = rng.normal(size=(10, 5))
    X[:, 2] = X[:, 1] * 2.0
    y = rng.normal(size=10)
    return {"X": X.tolist(), "y": y.tolist()}


def make_leak_case(rng):
    X = make_full_rank_matrix(rng)
    scale = rng.uniform(0.5, 3.0)
    if rng.integers(0, 2):
        scale = -scale
    y = X[:, 3] * scale
    return {"X": X.tolist(), "y": y.tolist()}


def test_sanitiser_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitiser script not found at {SCRIPT_PATH}"


def test_services_running():
    req = urllib.request.Request(
        "http://localhost:8080/ingest",
        data=json.dumps({"dummy": "data"}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as response:
            assert response.status == 200, "Expected HTTP 200 from Nginx/Flask"
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or Flask on 5000: {exc}")


def test_generated_corpus():
    rng = np.random.default_rng(secrets.randbits(128))
    cases = []
    for _ in range(50):
        cases.append((True, make_clean_case(rng)))
    for _ in range(25):
        cases.append((False, make_collinear_case(rng)))
    for _ in range(25):
        cases.append((False, make_leak_case(rng)))
    rng.shuffle(cases)

    failures = []
    initial_count = get_redis_ingest_count()

    with tempfile.TemporaryDirectory(prefix="validation_inputs_") as corpus_dir:
        for expected_clean, payload in cases:
            filename = secrets.token_hex(16) + ".json"
            path = os.path.join(corpus_dir, filename)
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)

            result = subprocess.run(
                [sys.executable, SCRIPT_PATH, path],
                capture_output=True,
            )
            if expected_clean and result.returncode != 0:
                failures.append(f"clean input {filename} was rejected")
            elif not expected_clean and result.returncode == 0:
                failures.append(f"evil input {filename} bypassed validation")

    final_count = get_redis_ingest_count()
    ingested = final_count - initial_count

    assert not failures, f"Sanitiser classification failures: {failures[:5]}"
    assert ingested == 50, f"Expected 50 clean ingestions in Redis, but got {ingested}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
