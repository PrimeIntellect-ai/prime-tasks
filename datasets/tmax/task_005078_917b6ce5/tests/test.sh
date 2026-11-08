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

backup="/tmp/target_metric.wav.verifier-backup"
cp /app/data/target_metric.wav "$backup"
restore_audio() {
    cp "$backup" /app/data/target_metric.wav 2>/dev/null || true
    rm -f "$backup"
}
trap restore_audio EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import time

import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8000/api/validate"
AUDIO = "/app/data/target_metric.wav"


def independently_computed_kl():
    rng = np.random.default_rng(seed=42)
    array = rng.random((1000, 1000), dtype=np.float32)
    row_sums = array.astype(np.float64).sum(axis=1)
    p = row_sums / row_sums.sum()
    q = np.full(1000, 1.0 / 1000.0, dtype=np.float64)
    return float(np.sum(p * np.log(p / q)))


def install_spoken_metric(tens, ones):
    words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    phrase = f"zero point {words[tens]} {words[ones]}"
    temporary = AUDIO + ".verifier-new.wav"
    subprocess.run(["espeak", "-w", temporary, phrase], check=True)
    os.replace(temporary, AUDIO)
    time.sleep(0.1)
    return (10 * tens + ones) / 100.0


def query_and_validate(expected_metric, expected_kl):
    try:
        response = requests.get(URL, timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.headers.get("content-type", "").lower().startswith("application/json")

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert isinstance(data, dict)
    assert set(data) == {"computed_kl_divergence", "expected_metric"}, \
        f"Response must contain exactly the two required fields, got {set(data)}"

    metric = data["expected_metric"]
    divergence = data["computed_kl_divergence"]
    assert isinstance(metric, (int, float)) and not isinstance(metric, bool)
    assert isinstance(divergence, (int, float)) and not isinstance(divergence, bool)
    assert math.isfinite(float(metric)) and math.isfinite(float(divergence))
    assert math.isclose(float(metric), expected_metric, rel_tol=0.0, abs_tol=1e-8), \
        f"Expected metric transcribed from current audio to be {expected_metric}, got {metric}"
    assert math.isclose(float(divergence), expected_kl, rel_tol=0.0, abs_tol=1e-12), \
        f"KL divergence does not match the specified NumPy computation: {divergence}"


def test_simulation_validation_service():
    expected_kl = independently_computed_kl()

    choices = [(a, b) for a in range(1, 10) for b in range(1, 10) if (a, b) != (0, 7)]
    first = secrets.choice(choices)
    second = secrets.choice([pair for pair in choices if pair != first])

    query_and_validate(install_spoken_metric(*first), expected_kl)
    query_and_validate(install_spoken_metric(*second), expected_kl)

    # The service must expose only the requested GET endpoint.
    token = secrets.token_hex(12)
    for path in ["/", "/api", f"/api/not-validate-{token}", "/docs", "/redoc", "/openapi.json"]:
        response = requests.get(f"http://127.0.0.1:8000{path}", timeout=5, allow_redirects=False)
        assert response.status_code == 404, \
            f"Unexpected GET endpoint at {path}: HTTP {response.status_code}"

    response = requests.post(URL, timeout=5, allow_redirects=False)
    assert response.status_code == 405, \
        f"/api/validate must be GET-only; POST returned HTTP {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
