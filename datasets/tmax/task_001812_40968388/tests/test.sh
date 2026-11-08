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
import secrets
import struct
import uuid
import zlib

import pytest
import requests

URL = "http://127.0.0.1:8000/api/v1/config/push"
HEADERS = {"Authorization": "Bearer track-configs-2024"}


def generate_payload(text: bytes, valid_checksum: bool = True) -> bytes:
    magic = b"CFG\x01"
    uncompressed_len = len(text)
    crc = zlib.crc32(text) & 0xFFFFFFFF
    checksum = crc ^ 0xDEADBEEF
    if not valid_checksum:
        checksum = (checksum ^ 0xFFFFFFFF) & 0xFFFFFFFF
    compressed = zlib.compress(text)
    return struct.pack(">4sII", magic, uncompressed_len, checksum) + compressed


def post(payload, headers=HEADERS):
    try:
        return requests.post(URL, headers=headers, data=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service: {exc}")


def test_base_configuration_initialized():
    expected = {}
    pattern = re.compile(r"^\[[^]]+\]\s+CONFIG_ADD\s+(\S+)\s+(.*)$")
    with open("/home/user/base_config.log", "r", encoding="utf-8") as source:
        for line in source:
            match = pattern.match(line.rstrip("\n"))
            if match:
                expected[match.group(1)] = match.group(2)

    assert expected, "No base configuration entries were parsed by the verifier."
    for key, value in expected.items():
        path = f"/home/user/config_store/{key}.conf"
        assert os.path.isfile(path), f"Base configuration file {path} was not initialized."
        with open(path, "r", encoding="utf-8") as stored:
            assert stored.read() == value, f"Initial value for {key} is incorrect."


def test_valid_config_push():
    text = b"TEST_KEY_1=100\nTEST_KEY_2=active\n"
    payload = generate_payload(text, valid_checksum=True)
    resp = post(payload)

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert data.get("status") == "applied", f"Expected status 'applied', got: {data.get('status')}"
    updated = data.get("updated_keys", [])
    assert "TEST_KEY_1" in updated, "TEST_KEY_1 missing from updated_keys"
    assert "TEST_KEY_2" in updated, "TEST_KEY_2 missing from updated_keys"

    store_path_1 = "/home/user/config_store/TEST_KEY_1.conf"
    store_path_2 = "/home/user/config_store/TEST_KEY_2.conf"
    assert os.path.exists(store_path_1), f"Expected config file {store_path_1} was not created."
    with open(store_path_1, "r") as stored:
        assert stored.read() == "100", "Content of TEST_KEY_1.conf does not match."
    assert os.path.exists(store_path_2), f"Expected config file {store_path_2} was not created."
    with open(store_path_2, "r") as stored:
        assert stored.read() == "active", "Content of TEST_KEY_2.conf does not match."


def test_random_arbitrary_config_patch():
    keys = [f"DYNAMIC_{uuid.uuid4().hex.upper()}" for _ in range(4)]
    values = [
        secrets.token_hex(17),
        f"mode={secrets.token_hex(9)}",
        f"value with spaces {secrets.token_hex(8)}",
        str(secrets.randbelow(2**31)),
    ]
    text = "".join(f"{key}={value}\n" for key, value in zip(keys, values)).encode("utf-8")
    resp = post(generate_payload(text))

    assert resp.status_code == 200, f"Random valid patch was rejected: {resp.status_code} {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert data.get("status") == "applied"
    assert data.get("updated_keys") == keys, "updated_keys does not match the submitted patch"

    for key, value in zip(keys, values):
        path = f"/home/user/config_store/{key}.conf"
        assert os.path.isfile(path), f"Random configuration file {path} was not created."
        with open(path, "r", encoding="utf-8") as stored:
            assert stored.read() == value


def test_invalid_checksum_push():
    text = b"BAD_KEY=1\n"
    payload = generate_payload(text, valid_checksum=False)
    resp = post(payload)
    assert resp.status_code == 400, f"Expected 400 Bad Request for invalid checksum, got {resp.status_code}. Response: {resp.text}"
    store_path = "/home/user/config_store/BAD_KEY.conf"
    assert not os.path.exists(store_path), "Config file created despite invalid checksum."


def test_random_invalid_checksum_has_no_side_effect():
    key = f"BADCRC_{uuid.uuid4().hex.upper()}"
    value = secrets.token_hex(16)
    resp = post(generate_payload(f"{key}={value}\n".encode(), valid_checksum=False))
    assert resp.status_code == 400, f"Expected 400 for random invalid checksum, got {resp.status_code}."
    assert not os.path.exists(f"/home/user/config_store/{key}.conf")


def test_magic_bytes_are_verified():
    key = f"BADMAGIC_{uuid.uuid4().hex.upper()}"
    payload = generate_payload(f"{key}={secrets.token_hex(12)}\n".encode())
    payload = b"NOPE" + payload[4:]
    resp = post(payload)
    assert resp.status_code == 400, f"Expected 400 for invalid magic bytes, got {resp.status_code}."
    assert not os.path.exists(f"/home/user/config_store/{key}.conf")


def test_declared_uncompressed_length_is_verified():
    for delta in (-1, 1, 97):
        key = f"BADLEN_{uuid.uuid4().hex.upper()}"
        text = f"{key}={secrets.token_hex(13)}\n".encode()
        payload = generate_payload(text)
        declared = len(text) + delta
        payload = payload[:4] + struct.pack(">I", declared) + payload[8:]
        resp = post(payload)
        assert resp.status_code == 400, f"Expected 400 for incorrect declared length, got {resp.status_code}."
        assert not os.path.exists(f"/home/user/config_store/{key}.conf")


def test_missing_or_invalid_auth():
    text = b"AUTH_KEY=1\n"
    payload = generate_payload(text, valid_checksum=True)

    resp1 = post(payload, headers={})
    assert resp1.status_code != 200, "Service accepted request without Authorization header."

    resp2 = post(payload, headers={"Authorization": "Bearer wrong-token"})
    assert resp2.status_code != 200, "Service accepted request with invalid Authorization header."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
