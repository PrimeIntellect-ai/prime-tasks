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
# test_final_state.py

import json
import os
import secrets
import subprocess
import requests
import pytest


def test_crash_time_file():
    """Verify that the crash time was correctly identified and written."""
    path = "/app/crash_time.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you create it?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_time = "2023-11-10T08:14:03Z"
    assert content == expected_time, f"Incorrect crash time in {path}. Expected '{expected_time}', got '{content}'"


def test_requirements_install():
    """Verify that requirements.txt has been fixed and installs without conflicts."""
    req_path = "/app/requirements.txt"
    assert os.path.isfile(req_path), f"File {req_path} is missing."

    result = subprocess.run(
        ["pip", "install", "-r", req_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"pip install failed due to conflicts or errors:\n{result.stderr}\n{result.stdout}"


@pytest.mark.parametrize("payload", [{}, {"user_id": None}])
def test_ingest_warns_and_continues_for_missing_or_null_user_id(payload):
    """Execute ingest.py and verify both user_id edge cases warn without stopping processing."""
    ingest_path = "/app/ingest.py"
    assert os.path.isfile(ingest_path), f"File {ingest_path} is missing."

    sentinel_user = "verifier-user-" + secrets.token_hex(8)
    edge_record = json.dumps({"id": "TXN-" + secrets.token_hex(4), "payload": payload})
    valid_record = json.dumps({"id": "TXN-" + secrets.token_hex(4), "payload": {"user_id": sentinel_user}})

    harness = r'''
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("submitted_ingest", "/app/ingest.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "process_data", None)):
    raise AssertionError("/app/ingest.py must provide a callable process_data")
module.process_data(sys.argv[1])
print("__EDGE_RETURNED__", flush=True)
module.process_data(sys.argv[2])
print("__VALID_RETURNED__", flush=True)
'''
    result = subprocess.run(
        ["python3", "-c", harness, edge_record, valid_record],
        capture_output=True,
        text=True,
        timeout=10,
    )
    combined = result.stdout + "\n" + result.stderr
    assert result.returncode == 0, f"ingest.py crashed on an edge-case record:\n{combined}"
    assert "__EDGE_RETURNED__" in combined, "process_data did not return after the edge-case record"
    assert "__VALID_RETURNED__" in combined, "processing did not continue to the following valid record"
    assert sentinel_user in combined, "the following valid record was not processed normally"
    assert "warn" in combined.lower(), f"No warning was logged for missing/null payload.user_id:\n{combined}"


def test_api_health_endpoint_success():
    """Verify the Node.js API is running on the correct port and accepts the correct API key."""
    url = "http://127.0.0.1:9092/health"
    headers = {"X-API-KEY": "KAPPA-881-ALPHA"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to {url}. Is the Node.js service running on port 9092?")
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code == 200, f"Expected 200 OK at {url} with correct API key, got {response.status_code}. Response: {response.text}"


def test_api_health_endpoint_unauthorized():
    """Verify the Node.js API rejects requests without the correct API key."""
    url = "http://127.0.0.1:9092/health"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to {url}. Is the Node.js service running on port 9092?")
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code in (401, 403), f"Expected 401 or 403 at {url} without API key, got {response.status_code}. The API must enforce the X-API-KEY header."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
