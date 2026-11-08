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
import glob
import io
import os
import re
import secrets
import subprocess
import tarfile

import pytest
import requests

URL = "http://127.0.0.1:9090/api/config"


def recover_expected_config():
    parts = sorted(glob.glob("/app/backup_parts/corrupt_backup.tar.gz.part*"))
    assert parts, "No archive parts were found"
    assert all(os.path.isfile(path) and not os.path.islink(path) for path in parts), "Archive parts must be regular files"

    archive_data = b"".join(open(path, "rb").read() for path in parts)
    with tarfile.open(fileobj=io.BytesIO(archive_data), mode="r:gz") as archive:
        matches = [m for m in archive.getmembers() if os.path.basename(m.name) == "bloated_system.conf" and m.isfile()]
        assert len(matches) == 1, "Archive must contain exactly one bloated_system.conf"
        extracted = archive.extractfile(matches[0])
        assert extracted is not None
        text = extracted.read().decode("utf-8")

    lines = text.splitlines()
    assert lines and lines[0] == "[SYSTEM_CONFIG]", "Configuration does not begin with [SYSTEM_CONFIG]"
    assert lines.count("[SYSTEM_CONFIG]") > 1, "Expected recursive duplicate configuration blocks"

    result = {}
    for line in lines[1:]:
        if line == "[SYSTEM_CONFIG]":
            break
        if not line.strip():
            continue
        assert "=" in line, f"Invalid configuration line: {line!r}"
        key, value = line.split("=", 1)
        assert key and key not in result, f"Invalid or duplicate key: {key!r}"
        result[key] = value
    assert result, "The first configuration block was empty"
    return result


def recover_token():
    source = "/app/api_token.png"
    assert os.path.isfile(source) and not os.path.islink(source), "Token image is missing or invalid"
    prepared = "/tmp/verifier_token.png"
    subprocess.run(
        ["convert", source, "-bordercolor", "white", "-border", "50", "-resize", "200%", prepared],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    outputs = []
    for psm in (6, 7, 11):
        proc = subprocess.run(
            ["tesseract", prepared, "stdout", "--psm", str(psm)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        outputs.append(proc.stdout)
        match = re.search(r"TOKEN\s*:\s*([A-Za-z0-9_]+)", proc.stdout, re.IGNORECASE)
        if match:
            return match.group(1)
    raise AssertionError(f"OCR could not recover TOKEN from image; outputs were: {outputs!r}")


EXPECTED_JSON = recover_expected_config()
CORRECT_TOKEN = recover_token()


def test_server_running():
    """Verify that the server is listening and responding to requests."""
    try:
        requests.get(URL, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Could not connect to the server at {URL}. Is it running? Error: {e}")


def test_valid_request():
    """Verify that the recovered token returns the recovered first configuration block."""
    headers = {"Authorization": f"Bearer {CORRECT_TOKEN}"}
    try:
        response = requests.get(URL, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but could not parse body: {response.text}")

    assert data == EXPECTED_JSON, f"JSON response does not match recovered output.\nExpected: {EXPECTED_JSON}\nGot: {data}"


def test_missing_auth():
    """Verify that a request missing the Authorization header returns 401 Unauthorized."""
    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request failed: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing auth, got {response.status_code}. Response: {response.text}"


def test_wrong_auth():
    """Retain the original fixed incorrect-token assertion."""
    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    try:
        response = requests.get(URL, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request failed: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for wrong auth, got {response.status_code}. Response: {response.text}"


def test_derived_wrong_auth():
    """Verify rejection of an unpredictable token distinct from the recovered token."""
    wrong = secrets.token_hex(24)
    while wrong == CORRECT_TOKEN:
        wrong = secrets.token_hex(24)
    response = requests.get(URL, headers={"Authorization": f"Bearer {wrong}"}, timeout=2)
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for derived wrong auth, got {response.status_code}. Response: {response.text}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
