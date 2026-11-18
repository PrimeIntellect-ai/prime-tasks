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
import importlib.util
import os
import random
import time
import uuid

import pytest
import requests

API_KEY = "secr3t_m@th_88"
TENANT_ID = "8472"
BASE_URL = "http://127.0.0.1:9090"
RNG = random.SystemRandom()


def wait_for_service():
    max_retries = 5
    for _ in range(max_retries):
        try:
            requests.get(f"{BASE_URL}/", timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(1)


def expected_ema(values, alpha=0.1):
    result = 0.0
    for value in values:
        result = alpha * value + (1 - alpha) * result
    return result


def post_concurrently(tenant_id, value, count):
    headers = {"X-API-Key": API_KEY}
    payload = {"uptime_ms": value}

    def send_ping():
        response = requests.post(
            f"{BASE_URL}/record_ping/{tenant_id}",
            json=payload,
            headers=headers,
            timeout=5,
        )
        return response.status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=count) as executor:
        futures = [executor.submit(send_ping) for _ in range(count)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]

    for status in results:
        assert status == 200, f"Expected status code 200, got {status}"


def read_ema(tenant_id):
    response = requests.get(
        f"{BASE_URL}/uptime/{tenant_id}",
        headers={"X-API-Key": API_KEY},
        timeout=5,
    )
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "ema" in data, "Response JSON missing 'ema' field"
    return data["ema"]


def test_00_server_artifact_and_formula():
    path = "/app/uptime_repo/server.py"
    assert os.path.isfile(path), "server.py is missing"

    spec = importlib.util.spec_from_file_location("submitted_uptime_server", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_ema", None)), "calculate_ema is missing"

    for _ in range(8):
        new_value = RNG.uniform(-5000, 5000)
        current = RNG.uniform(-5000, 5000)
        alpha = RNG.uniform(0.01, 0.99)
        expected = alpha * new_value + (1 - alpha) * current
        actual = module.calculate_ema(new_value, current, alpha)
        assert actual == pytest.approx(expected, rel=1e-10, abs=1e-10)


def test_01_service_running_and_correct():
    wait_for_service()
    headers = {"X-API-Key": API_KEY}

    num_requests = 50
    value = 100
    payload = {"uptime_ms": value}

    def send_ping():
        response = requests.post(
            f"{BASE_URL}/record_ping/{TENANT_ID}",
            json=payload,
            headers=headers,
            timeout=5,
        )
        return response.status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(send_ping) for _ in range(num_requests)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]

    for res in results:
        assert res == 200, f"Expected status code 200, got {res}"

    response = requests.get(f"{BASE_URL}/uptime/{TENANT_ID}", headers=headers, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    data = response.json()
    assert "ema" in data, "Response JSON missing 'ema' field"
    actual_ema = data["ema"]

    alpha = 0.1
    expected = value * (1 - (1 - alpha) ** num_requests)
    assert abs(actual_ema - expected) < 1e-4, (
        f"Expected EMA to be ~{expected}, but got {actual_ema}. This indicates either "
        "the math bug or the concurrency bug is not fully fixed."
    )


def test_02_authentication_is_enforced():
    tenant = f"auth-{uuid.uuid4().hex}"
    bad_headers = {"X-API-Key": f"wrong-{uuid.uuid4().hex}"}
    post = requests.post(
        f"{BASE_URL}/record_ping/{tenant}",
        json={"uptime_ms": RNG.uniform(1, 1000)},
        headers=bad_headers,
        timeout=5,
    )
    get = requests.get(f"{BASE_URL}/uptime/{tenant}", headers=bad_headers, timeout=5)
    assert post.status_code == 401
    assert get.status_code == 401


def test_03_randomized_sequential_ema():
    tenant = f"seq-{uuid.uuid4().hex}"
    values = [RNG.uniform(0.01, 10000.0) for _ in range(RNG.randint(6, 14))]
    headers = {"X-API-Key": API_KEY}

    for value in values:
        response = requests.post(
            f"{BASE_URL}/record_ping/{tenant}",
            json={"uptime_ms": value},
            headers=headers,
            timeout=5,
        )
        assert response.status_code == 200

    assert read_ema(tenant) == pytest.approx(expected_ema(values), rel=1e-8, abs=1e-6)


@pytest.mark.parametrize("case", range(3))
def test_04_randomized_concurrent_updates(case):
    tenant = f"concurrent-{case}-{uuid.uuid4().hex}"
    value = RNG.uniform(0.01, 10000.0)
    count = RNG.randint(24, 58)

    post_concurrently(tenant, value, count)
    expected = expected_ema([value] * count)
    assert read_ema(tenant) == pytest.approx(expected, rel=1e-8, abs=1e-5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
