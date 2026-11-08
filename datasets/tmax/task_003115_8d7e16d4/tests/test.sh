#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
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
import secrets
import signal
import socket
import subprocess
import time

import numpy as np
import pytest
import requests

SCRIPT_PATH = "/home/user/run_server.sh"
CSV_PATH = "/app/mutations.csv"
BASE_URL = "http://127.0.0.1:8000"
VALID_HEADERS = {"Authorization": "Bearer BIO-77X9"}


def wait_for_port(open_expected, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.5):
                is_open = True
        except OSError:
            is_open = False
        if is_open == open_expected:
            return True
        time.sleep(0.2)
    return False


def start_server():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"
    os.chmod(SCRIPT_PATH, 0o755)
    process = subprocess.Popen(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
    )
    pgid = os.getpgid(process.pid)
    if not wait_for_port(True, 30):
        try:
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        pytest.fail("Server did not start on port 8000 within 30 seconds.")
    return process, pgid


def stop_server(server):
    process, pgid = server
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    assert wait_for_port(False, 10), "Server did not release port 8000"


def expected_ci(scores):
    scores = np.asarray(scores, dtype=float)
    np.random.seed(42)
    means = [
        np.mean(np.random.choice(scores, size=len(scores), replace=True))
        for _ in range(1000)
    ]
    return np.percentile(means, 2.5), np.percentile(means, 97.5)


def assert_unauthorized(path):
    for headers in (
        None,
        {"Authorization": "Bearer WRONG-TOKEN"},
        {"Authorization": "BIO-77X9"},
        {"Authorization": "Bearer BIO-77X9-extra"},
    ):
        response = requests.get(BASE_URL + path, headers=headers, timeout=5)
        assert response.status_code == 401, (
            f"Expected 401 Unauthorized for {path} with headers {headers}, "
            f"got {response.status_code}: {response.text}"
        )


def assert_integral(t):
    response = requests.get(
        BASE_URL + "/integrate", params={"t": repr(t)}, headers=VALID_HEADERS, timeout=5
    )
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Could not parse JSON from response: {response.text}")
    assert "integral" in data, "Response JSON missing 'integral' key"
    expected = 1.5 * (t ** 3 / 3.0)
    assert abs(float(data["integral"]) - expected) < 1e-4, (
        f"Expected integral ~{expected}, got {data['integral']}"
    )


def assert_bootstrap(scores):
    response = requests.get(BASE_URL + "/bootstrap", headers=VALID_HEADERS, timeout=5)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Could not parse JSON from response: {response.text}")
    assert "ci_lower" in data, "Response JSON missing 'ci_lower' key"
    assert "ci_upper" in data, "Response JSON missing 'ci_upper' key"
    lower, upper = expected_ci(scores)
    assert abs(float(data["ci_lower"]) - lower) < 0.01, (
        f"Expected ci_lower ~{lower}, got {data['ci_lower']}"
    )
    assert abs(float(data["ci_upper"]) - upper) < 0.01, (
        f"Expected ci_upper ~{upper}, got {data['ci_upper']}"
    )


def test_complete_service_behavior():
    original_scores = [1.2, 1.5, 1.3, 1.7, 1.1, 1.9, 1.4, 1.6, 1.8, 1.5]
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    server = None
    try:
        server = start_server()

        # Preserve the original authentication checks and extend them to bad tokens
        # and both protected endpoints.
        assert_unauthorized("/integrate?t=5.0")
        assert_unauthorized("/bootstrap")

        # Preserve the original fixed-value assertion.
        assert_integral(5.0)

        # Exercise additional unpredictable inputs so a single hardcoded result fails.
        rng = secrets.SystemRandom()
        for _ in range(5):
            assert_integral(rng.uniform(0.2, 9.0))

        # Preserve the original bootstrap assertion against the provided CSV.
        assert_bootstrap(original_scores)

        stop_server(server)
        server = None

        # Replace the CSV with verifier-generated data and restart, ensuring the
        # application actually reads the dataset and performs the specified bootstrap.
        rng = secrets.SystemRandom()
        dynamic_scores = [round(rng.uniform(20.0, 80.0), 5) for _ in range(13)]
        with open(CSV_PATH, "w", encoding="utf-8") as f:
            f.write("score\n")
            for value in dynamic_scores:
                f.write(f"{value}\n")

        server = start_server()
        assert_bootstrap(dynamic_scores)
        assert_unauthorized("/bootstrap")
    finally:
        if server is not None:
            stop_server(server)
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
