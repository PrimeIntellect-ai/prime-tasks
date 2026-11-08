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
import concurrent.futures
import math
import random
import re
import subprocess
import uuid

import pytest
import requests

COLLECTOR_URL = "http://localhost:8081/ingest"
API_URL = "http://localhost:8082/sensors"
AUTH_TOKEN = "secret-token-99"
SUCCESS_CODES = {200, 201, 202, 204}


def send_valid_request(value):
    try:
        response = requests.post(
            COLLECTOR_URL,
            json={"sensor_id": "temp_1", "value": value},
            timeout=5,
        )
        return response.status_code
    except requests.RequestException as exc:
        return str(exc)


def post_value(sensor_id, value):
    return requests.post(
        COLLECTOR_URL,
        json={"sensor_id": sensor_id, "value": value},
        timeout=5,
    )


def read_value(sensor_id, token=AUTH_TOKEN):
    response = requests.get(
        f"{API_URL}/{sensor_id}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=5,
    )
    assert response.status_code == 200, (
        f"Expected HTTP 200 from API, got {response.status_code}. "
        f"Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        data = response.text.strip()

    if isinstance(data, dict):
        assert "value" in data or "average" in data, "Unexpected API response object"
        data = data.get("value", data.get("average"))

    try:
        value = float(data)
    except (TypeError, ValueError):
        pytest.fail(f"Could not parse API response as a float/JSON: {response.text}")

    assert math.isfinite(value), f"API returned a non-finite value: {value}"
    return value


def redis_value(sensor_id):
    result = subprocess.run(
        ["redis-cli", "--raw", "-h", "127.0.0.1", "-p", "6379", "GET", sensor_id],
        text=True,
        capture_output=True,
        timeout=5,
        check=True,
    )
    text = result.stdout.strip()
    assert text, f"Redis did not contain key {sensor_id}"
    value = float(text)
    assert math.isfinite(value), f"Redis contained a non-finite value: {text}"
    return value


def test_required_configuration():
    text = open("/home/user/app/config.env", encoding="utf-8").read()

    def setting(name):
        match = re.search(rf"(?m)^\s*{re.escape(name)}\s*=\s*([^#\r\n]*)", text)
        assert match, f"Missing {name} in config.env"
        return match.group(1).strip().strip("'\"")

    assert setting("REDIS_HOST") in {"localhost", "127.0.0.1"}
    assert setting("REDIS_PORT") == "6379"
    assert setting("API_TOKEN") == AUTH_TOKEN


def test_collector_malformed_json_handling():
    """Malformed payloads must return 400 without killing the collector."""
    try:
        response = requests.post(
            COLLECTOR_URL,
            json={"sensor_id": "temp_1", "value": "bad_string"},
            timeout=5,
        )
        assert response.status_code == 400, (
            f"Expected HTTP 400 for malformed JSON, got {response.status_code}"
        )

        response = requests.post(
            COLLECTOR_URL,
            data=b'{"sensor_id":',
            headers={"Content-Type": "application/json"},
            timeout=5,
        )
        assert response.status_code == 400, (
            f"Expected HTTP 400 for corrupted JSON, got {response.status_code}"
        )

        health = post_value("malformed_health_" + uuid.uuid4().hex, 12.5)
        assert health.status_code in SUCCESS_CODES, "Collector died after malformed JSON"
    except requests.ConnectionError:
        pytest.fail("Collector service is not running or crashed upon receiving malformed JSON.")


def test_collector_concurrent_requests():
    """Retain the original concurrent successful-request assertion."""
    num_requests = 100
    values = [20.0 + (i % 10) for i in range(num_requests)]

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(send_valid_request, values))

    for result in results:
        assert result in SUCCESS_CODES, f"Expected successful status code, got {result}"


def test_api_authenticated_read():
    """Retain the original authenticated, parseable, non-NaN read assertion."""
    try:
        value = read_value("temp_1")
        assert not math.isnan(value), "API returned NaN"
    except requests.ConnectionError:
        pytest.fail("API service is not running on port 8082.")


def test_exact_sequential_ema_and_redis_storage():
    """Check the required EMA formula using verifier-generated values."""
    rng = random.SystemRandom()
    sensor_id = "seq_" + uuid.uuid4().hex
    values = [rng.uniform(-80.0, 180.0) for _ in range(9)]

    expected = values[0]
    response = post_value(sensor_id, values[0])
    assert response.status_code in SUCCESS_CODES

    for value in values[1:]:
        expected = expected * 0.9 + value * 0.1
        response = post_value(sensor_id, value)
        assert response.status_code in SUCCESS_CODES

    actual = read_value(sensor_id)
    stored = redis_value(sensor_id)
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8), (
        f"Incorrect EMA: expected {expected}, got {actual}"
    )
    assert math.isclose(stored, expected, rel_tol=1e-10, abs_tol=1e-8), (
        f"Redis value is incorrect: expected {expected}, got {stored}"
    )


def test_concurrent_updates_are_atomic():
    """Equal concurrent inputs have an order-independent expected EMA."""
    rng = random.SystemRandom()
    sensor_id = "concurrent_" + uuid.uuid4().hex
    initial = rng.uniform(-40.0, 20.0)
    target = rng.uniform(90.0, 180.0)
    count = 40

    response = post_value(sensor_id, initial)
    assert response.status_code in SUCCESS_CODES

    def update(_):
        try:
            return post_value(sensor_id, target).status_code
        except requests.RequestException as exc:
            return str(exc)

    with concurrent.futures.ThreadPoolExecutor(max_workers=40) as executor:
        statuses = list(executor.map(update, range(count)))

    for status in statuses:
        assert status in SUCCESS_CODES, f"Concurrent update failed: {status}"

    expected = initial
    for _ in range(count):
        expected = expected * 0.9 + target * 0.1

    actual = read_value(sensor_id)
    stored = redis_value(sensor_id)
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8), (
        f"Concurrent EMA updates were lost or unstable: expected {expected}, got {actual}"
    )
    assert math.isclose(stored, expected, rel_tol=1e-10, abs_tol=1e-8), (
        f"Redis does not contain the atomic EMA result: expected {expected}, got {stored}"
    )


def test_api_rejects_bad_authentication():
    response = requests.get(
        f"{API_URL}/temp_1",
        headers={"Authorization": "Bearer wrong-token"},
        timeout=5,
    )
    assert response.status_code == 401
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
