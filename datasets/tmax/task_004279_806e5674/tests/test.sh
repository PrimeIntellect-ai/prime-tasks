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
import importlib.util
import os
import re
import secrets
import subprocess
import threading
import time

import pytest
import requests
from flask import Flask
from werkzeug.serving import make_server

BASE_URL = "http://127.0.0.1:8000"


def wait_for_service(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


@pytest.fixture(scope="module", autouse=True)
def check_service_running():
    assert wait_for_service(f"{BASE_URL}/status"), "The service is not running or not reachable on 127.0.0.1:8000."


@pytest.fixture(scope="module")
def forensic_credentials():
    ocr = subprocess.run(
        ["tesseract", "/app/clue.png", "stdout", "--psm", "6"],
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
    ).stdout
    override_match = re.search(
        r"SYSTEM[\s_]*OVERRIDE[\s_]*CODE\s*=\s*([A-Za-z0-9_-]+)",
        ocr,
        re.IGNORECASE,
    )
    assert override_match, f"Could not derive SYSTEM_OVERRIDE_CODE from OCR output: {ocr!r}"

    with open("/app/memory.dmp", "rb") as dump:
        memory = dump.read()
    session_match = re.search(rb"DEBUG_SESSION_ID=([A-Za-z0-9_-]+)", memory)
    assert session_match, "Could not derive DEBUG_SESSION_ID from memory dump"

    return override_match.group(1), session_match.group(1).decode("ascii")


@pytest.fixture(scope="module")
def source_url():
    assert os.path.isfile("/app/server.py"), "/app/server.py is missing or is not a regular file"

    spec = importlib.util.spec_from_file_location("submitted_server", "/app/server.py")
    assert spec is not None and spec.loader is not None, "Unable to load /app/server.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    app = getattr(module, "app", None)
    assert isinstance(app, Flask), "/app/server.py must define a Flask application named app"

    server = make_server("127.0.0.1", 0, app)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}"
    assert wait_for_service(f"{url}/status"), "The application in /app/server.py could not be started"
    try:
        yield url
    finally:
        server.shutdown()
        thread.join(timeout=3)


def test_status_missing_headers():
    response = requests.get(f"{BASE_URL}/status", timeout=3)
    assert response.status_code == 400, f"Expected HTTP 400 for missing headers, got {response.status_code}"


def test_status_valid_credentials():
    headers = {
        "X-Override-Code": "OMEGA77",
        "X-Session-Id": "9928374"
    }
    response = requests.get(f"{BASE_URL}/status", headers=headers, timeout=3)
    assert response.status_code == 200, f"Expected HTTP 200 for valid credentials, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert data.get("status") == "recovered", f"Expected JSON payload {{'status': 'recovered'}}, got {data}"


def test_status_invalid_credentials():
    headers = {
        "X-Override-Code": "INVALID",
        "X-Session-Id": "0000000"
    }
    response = requests.get(f"{BASE_URL}/status", headers=headers, timeout=3)
    assert response.status_code != 200, "Expected non-200 status code for invalid credentials"
    assert response.status_code != 500, "Service crashed (HTTP 500) with invalid credentials"


def test_running_service_uses_forensic_credentials(forensic_credentials):
    override, session = forensic_credentials
    response = requests.get(
        f"{BASE_URL}/status",
        headers={"X-Override-Code": override, "X-Session-Id": session},
        timeout=3,
    )
    assert response.status_code == 200
    assert response.json() == {"status": "recovered"}


def test_server_source_valid_credentials(source_url, forensic_credentials):
    override, session = forensic_credentials
    response = requests.get(
        f"{source_url}/status",
        headers={"X-Override-Code": override, "X-Session-Id": session},
        timeout=3,
    )
    assert response.status_code == 200
    assert response.json() == {"status": "recovered"}


@pytest.mark.parametrize("target_fixture", ["source_url", "running"])
def test_randomized_missing_and_malformed_headers(request, target_fixture, forensic_credentials):
    url = BASE_URL if target_fixture == "running" else request.getfixturevalue("source_url")
    override, session = forensic_credentials
    malformed_session = "bad-" + secrets.token_hex(10)

    cases = [
        {},
        {"X-Override-Code": override},
        {"X-Session-Id": session},
        {"X-Override-Code": override, "X-Session-Id": malformed_session},
        {"X-Override-Code": "", "X-Session-Id": session},
    ]
    for headers in cases:
        response = requests.get(f"{url}/status", headers=headers, timeout=3)
        assert response.status_code == 400, (
            f"Expected HTTP 400 for missing or malformed headers {headers!r}, "
            f"got {response.status_code}"
        )


def test_randomized_invalid_credentials_on_source(source_url, forensic_credentials):
    override, session = forensic_credentials
    bad_override = "BAD" + secrets.token_hex(12).upper()
    bad_session = str(secrets.randbelow(8_000_000) + 1_000_000)
    if bad_override == override:
        bad_override += "X"
    if bad_session == session:
        bad_session = str(int(bad_session) + 1)

    for headers in (
        {"X-Override-Code": bad_override, "X-Session-Id": session},
        {"X-Override-Code": override, "X-Session-Id": bad_session},
        {"X-Override-Code": bad_override, "X-Session-Id": bad_session},
    ):
        response = requests.get(f"{source_url}/status", headers=headers, timeout=3)
        assert response.status_code not in (200, 500), (
            f"Invalid credentials {headers!r} returned {response.status_code}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
