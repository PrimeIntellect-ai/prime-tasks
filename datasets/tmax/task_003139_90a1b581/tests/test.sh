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
import re
import subprocess
import uuid
from pathlib import Path

import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer FINOPS_SECRET_99X"}
IMAGE_PATH = Path("/app/transit_costs.png")


def extracted_costs():
    assert IMAGE_PATH.is_file(), f"Missing required input image: {IMAGE_PATH}"
    result = subprocess.run(
        ["tesseract", str(IMAGE_PATH), "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=True,
    )
    records = re.findall(
        r"Region\s*:\s*([^,\r\n]+?)\s*,\s*Cost\s*:\s*\$?([0-9]+(?:\.[0-9]+)?)\s*/\s*GB",
        result.stdout,
        flags=re.IGNORECASE,
    )
    assert records, f"Tesseract produced no parseable pricing records: {result.stdout!r}"

    costs = {}
    for region, cost in records:
        region = region.strip()
        assert region not in costs, f"Duplicate OCR region: {region}"
        costs[region] = cost
    return costs


def test_health_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health endpoint: {e}")

    assert response.status_code == 200, f"Expected status 200 for /health, got {response.status_code}"
    assert response.text.strip() == "OK", f"Expected body 'OK' for /health, got {response.text}"


def test_cost_endpoint_no_auth():
    try:
        response = requests.get(f"{BASE_URL}/cost?region=eu-central-1", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /cost endpoint: {e}")

    assert response.status_code == 401, f"Expected status 401 for missing auth, got {response.status_code}"


def test_cost_endpoint_wrong_auth():
    try:
        response = requests.get(
            f"{BASE_URL}/cost?region=ap-northeast-1",
            headers={"Authorization": "Bearer WRONG_TOKEN"},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /cost endpoint: {e}")

    assert response.status_code == 401, f"Expected status 401 for wrong auth, got {response.status_code}"


@pytest.mark.parametrize("region, expected_cost", [
    ("us-east-1", "0.02"),
    ("eu-central-1", "0.04"),
    ("ap-northeast-1", "0.09"),
    ("sa-east-1", "0.15"),
])
def test_cost_endpoint_valid_regions(region, expected_cost):
    try:
        response = requests.get(
            f"{BASE_URL}/cost?region={region}",
            headers=AUTH_HEADER,
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /cost endpoint: {e}")

    assert response.status_code == 200, f"Expected status 200 for region {region}, got {response.status_code}"
    assert response.text.strip() == expected_cost, f"Expected cost '{expected_cost}' for region {region}, got '{response.text}'"


def test_cost_endpoint_invalid_region():
    try:
        response = requests.get(
            f"{BASE_URL}/cost?region=invalid-region-99",
            headers=AUTH_HEADER,
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /cost endpoint: {e}")

    assert response.status_code == 404, f"Expected status 404 for invalid region, got {response.status_code}"


def test_every_ocr_derived_record_and_authentication():
    for region, expected_cost in extracted_costs().items():
        response = requests.get(
            f"{BASE_URL}/cost",
            params={"region": region},
            headers=AUTH_HEADER,
            timeout=5,
        )
        assert response.status_code == 200, (
            f"Expected status 200 for OCR-derived region {region!r}, got {response.status_code}"
        )
        assert response.text.strip() == expected_cost, (
            f"Expected OCR-derived cost {expected_cost!r} for {region!r}, got {response.text!r}"
        )

        for headers in ({}, {"Authorization": "Bearer WRONG_TOKEN"}):
            unauthorized = requests.get(
                f"{BASE_URL}/cost",
                params={"region": region},
                headers=headers,
                timeout=5,
            )
            assert unauthorized.status_code == 401, (
                f"Expected 401 for {region!r} with invalid authentication, "
                f"got {unauthorized.status_code}"
            )


def test_fresh_unknown_region_is_not_found():
    known = extracted_costs()
    while True:
        region = f"unknown-{uuid.uuid4().hex}"
        if region not in known:
            break
    response = requests.get(
        f"{BASE_URL}/cost",
        params={"region": region},
        headers=AUTH_HEADER,
        timeout=5,
    )
    assert response.status_code == 404, (
        f"Expected 404 for fresh unknown region {region!r}, got {response.status_code}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
