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
import math
import requests
import pytest
import time

BASE_URL = "http://127.0.0.1:8888"
COMPUTE_URL = f"{BASE_URL}/compute"
AUTH_TOKEN = "token_xyz_98765"
HEADERS = {"Authorization": f"Bearer {AUTH_TOKEN}"}


def wait_for_service():
    """Wait for the service to be up and running."""
    max_retries = 10
    for _ in range(max_retries):
        try:
            requests.get(BASE_URL, timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    pytest.fail("Service is not running or not reachable at 127.0.0.1:8888")


@pytest.fixture(scope="module", autouse=True)
def setup():
    wait_for_service()


def test_authentication_required():
    """Test that authentication is required."""
    response = requests.post(COMPUTE_URL, json={"value": 10}, timeout=2)
    assert response.status_code in [401, 403], (
        f"Expected 401 or 403 for unauthenticated request, got {response.status_code}"
    )


def test_incorrect_authentication_rejected():
    """Test that a bearer token other than the recovered token is rejected."""
    wrong_headers = {"Authorization": "Bearer token_xyz_98764"}
    response = requests.post(
        COMPUTE_URL, json={"value": 10}, headers=wrong_headers, timeout=2
    )
    assert response.status_code in [401, 403], (
        f"Expected 401 or 403 for an incorrect token, got {response.status_code}"
    )


def test_poison_pill_handling():
    """Test that the service handles the poison pill gracefully."""
    response = requests.post(COMPUTE_URL, json={"value": -1}, headers=HEADERS, timeout=2)
    assert response.status_code == 400, (
        f"Expected 400 Bad Request for poison pill payload, got {response.status_code}"
    )


def test_mathematical_correctness():
    """Test that the existing sqrt computation uses the extracted modulus."""
    value = 10
    response = requests.post(
        COMPUTE_URL, json={"value": value}, headers=HEADERS, timeout=2
    )
    assert response.status_code == 200, (
        f"Expected 200 OK for valid payload, got {response.status_code}. Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert "result" in data, "Response JSON is missing 'result' key"
    expected = math.sqrt(value) * 9973
    assert data["result"] == pytest.approx(expected), (
        f"Expected result to be sqrt({value}) * 9973 ({expected}), got {data['result']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
