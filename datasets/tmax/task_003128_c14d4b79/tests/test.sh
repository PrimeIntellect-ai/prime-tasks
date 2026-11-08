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

import os
import secrets
import shutil
import stat
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8123/metrics"
AUTH_HEADERS = {"X-Vault-Auth": "the access code is crimson butterfly protocol"}


def test_filesystem_state():
    """Test the filesystem state for the vault."""
    vault_dir = "/home/user/vault"
    data_dir = os.path.join(vault_dir, "data")
    active_data = os.path.join(vault_dir, "active_data")
    app_users = os.path.join(vault_dir, "app_users.conf")

    # Check vault dir permissions
    assert os.path.isdir(vault_dir), f"{vault_dir} is not a directory."
    vault_stat = os.stat(vault_dir)
    assert stat.S_IMODE(vault_stat.st_mode) == 0o700, f"Permissions of {vault_dir} are not 0700."

    # Check data dir and chunks
    assert os.path.isdir(data_dir), f"{data_dir} is not a directory."
    chunk1 = os.path.join(data_dir, "chunk1.dat")
    chunk2 = os.path.join(data_dir, "chunk2.dat")
    chunk3 = os.path.join(data_dir, "chunk3.dat")

    assert os.path.isfile(chunk1), f"{chunk1} is missing."
    assert os.path.isfile(chunk2), f"{chunk2} is missing."
    assert os.path.isfile(chunk3), f"{chunk3} is missing."

    assert os.path.getsize(chunk1) == 1024, f"{chunk1} size is not 1024 bytes."
    assert os.path.getsize(chunk2) == 2048, f"{chunk2} size is not 2048 bytes."
    assert os.path.getsize(chunk3) == 4096, f"{chunk3} size is not 4096 bytes."

    # Check symlink
    assert os.path.islink(active_data), f"{active_data} is not a symlink."
    assert os.readlink(active_data) == "/home/user/vault/data", f"{active_data} does not point to /home/user/vault/data."

    # Check app_users.conf
    assert os.path.isfile(app_users), f"{app_users} is missing."
    app_users_stat = os.stat(app_users)
    assert stat.S_IMODE(app_users_stat.st_mode) == 0o400, f"Permissions of {app_users} are not 0400."

    with open(app_users, "r") as f:
        content = f.read().strip()
    expected_content = "api_admin:x:1001:1001:API Administrator:/home/user/vault:/bin/false"
    assert content == expected_content, f"Content of {app_users} is incorrect."


def test_api_unauthorized():
    """Test that the API returns 401 Unauthorized without correct header."""
    # Missing header
    try:
        response = requests.get(URL, timeout=5)
        assert response.status_code == 401, f"Expected 401 for missing header, got {response.status_code}."
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    # Wrong header
    try:
        response = requests.get(URL, headers={"X-Vault-Auth": "wrong password"}, timeout=5)
        assert response.status_code == 401, f"Expected 401 for wrong header, got {response.status_code}."
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")


def test_api_authorized():
    """Test that the API returns 200 OK and correct JSON with correct header."""
    try:
        response = requests.get(URL, headers=AUTH_HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"

        data = response.json()
        assert data.get("status") == "secure", "Expected status to be 'secure'."
        assert data.get("total_bytes") == 7168, f"Expected total_bytes to be 7168, got {data.get('total_bytes')}."
        assert data.get("acl_present") is True, "Expected acl_present to be True."
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response text: {response.text}")


def calculate_total(root):
    total = 0
    for directory, _, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(directory, filename)
            if os.path.isfile(path):
                total += os.path.getsize(path)
    return total


def get_authorized_json():
    try:
        response = requests.get(URL, headers=AUTH_HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
        return response.json()
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response text: {response.text}")


def test_api_dynamically_recalculates_metrics():
    """Mutate unpredictable filesystem state and require fresh metrics."""
    vault_dir = "/home/user/vault"
    data_dir = os.path.join(vault_dir, "data")
    active_data = os.path.join(vault_dir, "active_data")
    app_users = os.path.join(vault_dir, "app_users.conf")
    acl_backup = os.path.join(vault_dir, f".app_users.{uuid.uuid4().hex}.bak")
    dynamic_dir = os.path.join(data_dir, f"dynamic_{uuid.uuid4().hex}")
    acl_moved = False

    try:
        os.mkdir(dynamic_dir)
        first_size = 300 + secrets.randbelow(5000)
        second_size = 300 + secrets.randbelow(5000)
        with open(os.path.join(dynamic_dir, f"first_{uuid.uuid4().hex}.dat"), "wb") as f:
            f.write(os.urandom(first_size))
        with open(os.path.join(dynamic_dir, f"second_{uuid.uuid4().hex}.dat"), "wb") as f:
            f.write(os.urandom(second_size))

        expected_total = calculate_total(active_data)
        assert expected_total != 7168
        data = get_authorized_json()
        assert data.get("status") == "secure", "Expected status to be 'secure'."
        assert data.get("total_bytes") == expected_total, (
            f"Expected dynamically calculated total_bytes {expected_total}, got {data.get('total_bytes')}."
        )
        assert data.get("acl_present") is True, "Expected acl_present to remain True."

        os.rename(app_users, acl_backup)
        acl_moved = True
        data = get_authorized_json()
        assert data.get("status") == "secure", "Expected status to be 'secure'."
        assert data.get("total_bytes") == calculate_total(active_data), "total_bytes changed unexpectedly."
        assert data.get("acl_present") is False, "Expected acl_present to become False after ACL removal."
    finally:
        if acl_moved and os.path.exists(acl_backup):
            os.rename(acl_backup, app_users)
        shutil.rmtree(dynamic_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
