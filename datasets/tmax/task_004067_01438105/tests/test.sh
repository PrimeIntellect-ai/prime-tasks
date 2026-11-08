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
import base64
import hashlib
import secrets
from pathlib import Path

import pytest
import requests

KEY = b"s3cr3tK3y1234567"
URL = "http://127.0.0.1:9000/execute"
SANDBOX = Path("/tmp/sandbox")


def encrypt_payload(plaintext: bytes) -> str:
    xored = bytes([b ^ KEY[i % len(KEY)] for i, b in enumerate(plaintext)])
    return base64.b64encode(xored).decode("utf-8")


def get_checksum(plaintext: bytes) -> str:
    return hashlib.sha256(plaintext).hexdigest()


def post_command(command: bytes, checksum=None):
    if checksum is None:
        checksum = get_checksum(command)
    return requests.post(
        URL,
        json={"payload": encrypt_payload(command), "checksum": checksum},
        timeout=5,
    )


def test_service_running_and_executes_command():
    command = b"echo 'hello world'"
    payload = encrypt_payload(command)
    checksum = get_checksum(command)

    try:
        response = requests.post(URL, json={"payload": payload, "checksum": checksum}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert "hello world" in response.text, f"Expected 'hello world' in stdout, got: {response.text}"


def test_service_invalid_checksum():
    command = b"echo 'should not run'"
    payload = encrypt_payload(command)
    checksum = "invalidchecksum1234567890abcdef"

    try:
        response = requests.post(URL, json={"payload": payload, "checksum": checksum}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 403, f"Expected HTTP 403 Forbidden for invalid checksum, got {response.status_code}"


def test_service_runs_in_sandbox_directory():
    command = b"pwd"
    payload = encrypt_payload(command)
    checksum = get_checksum(command)

    try:
        response = requests.post(URL, json={"payload": payload, "checksum": checksum}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert "/tmp/sandbox" in response.text, f"Expected execution in /tmp/sandbox, got: {response.text}"


def test_randomized_payloads_are_decrypted_and_executed_exactly():
    assert SANDBOX.is_dir(), "/tmp/sandbox was not created"

    for _ in range(3):
        token = secrets.token_hex(18)
        filename = f"verifier_{secrets.token_hex(10)}.txt"
        output_path = SANDBOX / filename
        output_path.unlink(missing_ok=True)
        command = f"printf '%s' '{token}' > '{filename}'; cat '{filename}'".encode()

        response = post_command(command)
        assert response.status_code == 200
        assert response.text == token, f"Expected exact command stdout {token!r}, got {response.text!r}"
        assert output_path.is_file(), "Command did not create its relative file in /tmp/sandbox"
        assert output_path.read_text() == token
        output_path.unlink()

    left = secrets.randbelow(9000) + 1000
    right = secrets.randbelow(9000) + 1000
    expected = str(left * right + 37)
    command = f"printf '%s' \"$(({left} * {right} + 37))\"".encode()
    response = post_command(command)
    assert response.status_code == 200
    assert response.text == expected


def test_random_valid_looking_wrong_checksum_prevents_execution():
    marker = SANDBOX / f"forbidden_{secrets.token_hex(12)}.txt"
    marker.unlink(missing_ok=True)
    token = secrets.token_hex(16)
    command = f"printf '%s' '{token}' > '{marker.name}'".encode()

    wrong_checksum = get_checksum(secrets.token_bytes(48))
    assert wrong_checksum != get_checksum(command)
    response = post_command(command, wrong_checksum)

    assert response.status_code == 403, f"Expected 403 for a mismatched SHA256, got {response.status_code}"
    assert not marker.exists(), "Command with a mismatched checksum was executed"

    response = post_command(command)
    assert response.status_code == 200
    assert marker.read_text() == token, "The correctly checksummed command was not executed"
    marker.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
