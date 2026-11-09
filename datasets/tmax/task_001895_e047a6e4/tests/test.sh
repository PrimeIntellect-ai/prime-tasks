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
import hashlib
import os
import re
import secrets
import string
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"


def read_secret() -> str:
    result = subprocess.run(
        ["tesseract", "/app/policy_secret.png", "stdout", "--psm", "7"],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    match = re.search(r"POLICY_SEED:\s*(\S+)", result.stdout)
    assert match, f"Could not extract POLICY_SEED from image: {result.stdout!r}"
    return match.group(1)


SECRET = read_secret()


def get_expected_token(username: str) -> str:
    data = f"{username}{SECRET}"
    sig = hashlib.sha256(data.encode("utf-8")).hexdigest()
    return f"{username}:{sig}"


def random_username(prefix: str) -> str:
    alphabet = string.ascii_letters + string.digits + "_-"
    return prefix + "_" + "".join(secrets.choice(alphabet) for _ in range(24))


def post_json(path: str, payload: dict):
    try:
        return requests.post(f"{BASE_URL}{path}", json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to {path} failed: {exc}")


def test_service_running():
    """Verify the service is running and accepting connections."""
    try:
        requests.get(BASE_URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:8080 or refused connection.")
    except requests.exceptions.RequestException:
        pass


def test_generate_endpoint():
    """Verify the /generate endpoint returns the correct token format."""
    username = "alice"
    expected_token = get_expected_token(username)
    response = post_json("/generate", {"user": username})
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()
    assert "token" in data, "Response JSON missing 'token' key"
    assert data["token"] == expected_token, f"Expected token {expected_token}, got {data['token']}"


def test_validate_endpoint_valid():
    """Verify the /validate endpoint correctly validates a good token."""
    token = get_expected_token("alice")
    response = post_json("/validate", {"token": token})
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()
    assert "valid" in data, "Response JSON missing 'valid' key"
    assert data["valid"] is True, f"Expected valid=True, got {data['valid']}"


def test_validate_endpoint_invalid_hash():
    """Verify the /validate endpoint rejects a token with an incorrect hash."""
    token = "alice:wronghash12345"
    response = post_json("/validate", {"token": token})
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()
    assert "valid" in data, "Response JSON missing 'valid' key"
    assert data["valid"] is False, f"Expected valid=False, got {data['valid']}"


def test_validate_endpoint_invalid_user():
    """Verify the /validate endpoint rejects a token with a mismatched user."""
    alice_token = get_expected_token("alice")
    alice_hash = alice_token.split(":")[1]
    token = f"bob:{alice_hash}"
    response = post_json("/validate", {"token": token})
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()
    assert "valid" in data, "Response JSON missing 'valid' key"
    assert data["valid"] is False, f"Expected valid=False, got {data['valid']}"


def test_randomized_generation_and_validation():
    """Exercise general behavior with unpredictable usernames and signatures."""
    generated_users = [random_username("generate") for _ in range(6)]
    for username in generated_users:
        expected = get_expected_token(username)
        response = post_json("/generate", {"user": username})
        assert response.status_code == 200
        data = response.json()
        assert data.get("token") == expected

    # These users were never sent to /generate, so validation cannot rely on a cache.
    validation_users = [random_username("validate") for _ in range(6)]
    for username in validation_users:
        expected = get_expected_token(username)

        response = post_json("/validate", {"token": expected})
        assert response.status_code == 200
        assert response.json().get("valid") is True

        good_hash = expected.rsplit(":", 1)[1]
        replacement = "0" if good_hash[0] != "0" else "1"
        bad_hash = replacement + good_hash[1:]
        response = post_json("/validate", {"token": f"{username}:{bad_hash}"})
        assert response.status_code == 200
        assert response.json().get("valid") is False

        other_user = random_username("mismatch")
        response = post_json("/validate", {"token": f"{other_user}:{good_hash}"})
        assert response.status_code == 200
        assert response.json().get("valid") is False


def listener_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="utf-8") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def test_listener_is_go_program():
    """Verify that the process serving the required address is a Go executable."""
    inodes = listener_inodes()
    assert inodes, "No TCP listener found on 127.0.0.1:8080"

    matching_pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    matching_pids.add(entry)
        except OSError:
            continue

    assert matching_pids, "Could not identify the process listening on 127.0.0.1:8080"
    for pid in matching_pids:
        result = subprocess.run(
            ["go", "version", "-m", f"/proc/{pid}/exe"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and "go1." in (result.stdout + result.stderr):
            return
    pytest.fail("The process listening on 127.0.0.1:8080 is not a Go executable")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
