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
import os
import re
import subprocess
import tarfile

import pytest
import requests


def derive_expected_values():
    directive_path = "/app/restore_directive.png"
    assert os.path.isfile(directive_path), f"File not found: {directive_path}"

    result = subprocess.run(
        ["tesseract", directive_path, "stdout"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"OCR failed: {result.stderr}"
    directive = result.stdout

    archives = re.findall(r"^Archive:\s*(\S+)\s*$", directive, re.MULTILINE)
    keys = re.findall(r"^RecoveryKey:\s*(\S+)\s*$", directive, re.MULTILINE)
    ports = re.findall(r"^ServerPort:\s*(\d+)\s*$", directive, re.MULTILINE)
    assert len(archives) == 1, f"Could not uniquely derive Archive from OCR output: {directive!r}"
    assert len(keys) == 1, f"Could not uniquely derive RecoveryKey from OCR output: {directive!r}"
    assert len(ports) == 1, f"Could not uniquely derive ServerPort from OCR output: {directive!r}"

    archive_path = archives[0]
    recovery_key = keys[0]
    port = int(ports[0])
    assert 1 <= port <= 65535, f"Invalid ServerPort: {port}"
    assert os.path.isfile(archive_path), f"Archive from directive not found: {archive_path}"

    with tarfile.open(archive_path, mode="r:gz") as archive:
        members = [
            member for member in archive.getmembers()
            if member.isfile() and os.path.basename(member.name) == "disk_info.log"
        ]
        assert len(members) == 1, "Archive must contain exactly one disk_info.log file"
        extracted = archive.extractfile(members[0])
        assert extracted is not None, "Could not read disk_info.log from archive"
        disk_info = extracted.read().decode("utf-8").strip()

    match = re.fullmatch(
        r"Device:\s*([^,]+),\s*Mountpoint:\s*([^,]+),\s*Type:\s*([^,]+),\s*Options:\s*(.+)",
        disk_info,
    )
    assert match is not None, f"Unexpected disk_info.log format: {disk_info!r}"
    device, mountpoint, fs_type, options = (part.strip() for part in match.groups())
    expected_fstab = f"{device} {mountpoint} {fs_type} {options} 0 2"
    return recovery_key, port, expected_fstab


EXPECTED_KEY, SERVER_PORT, EXPECTED_FSTAB = derive_expected_values()
BASE_URL = f"http://127.0.0.1:{SERVER_PORT}"


def test_parsed_fstab_file():
    """Verify that the parsed fstab configuration file was created correctly."""
    fstab_path = "/app/parsed_fstab.conf"
    assert os.path.isfile(fstab_path), f"File not found: {fstab_path}"

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_FSTAB, (
        f"Expected fstab content '{EXPECTED_FSTAB}', but got '{content}'"
    )


def test_http_server_health_endpoint():
    """Verify the /health endpoint of the HTTP server."""
    url = f"{BASE_URL}/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"

    try:
        json_data = response.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON")

    assert json_data == {"status": "ok"}, f"Expected JSON {{'status': 'ok'}}, but got {json_data}"


def test_http_server_key_endpoint():
    """Verify the /key endpoint of the HTTP server."""
    url = f"{BASE_URL}/key"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}"
    content = response.text.strip()
    assert content == EXPECTED_KEY, f"Expected key '{EXPECTED_KEY}', but got '{content}'"


def test_http_server_fstab_endpoint():
    """Verify the /fstab endpoint of the HTTP server."""
    url = f"{BASE_URL}/fstab"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}"
    content = response.text.strip()
    assert content == EXPECTED_FSTAB, f"Expected fstab '{EXPECTED_FSTAB}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
