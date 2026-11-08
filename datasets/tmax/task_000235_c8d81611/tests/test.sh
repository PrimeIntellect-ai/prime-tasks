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
import json
import secrets
import string
import subprocess

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:8080/transform"
ORACLE = "/app/legacy_transformer"


def oracle_output(payload):
    completed = subprocess.run(
        [ORACLE],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert completed.returncode == 0, (
        f"Legacy transformer exited with {completed.returncode}: "
        f"{completed.stderr!r}"
    )
    return completed.stdout


def post(payload):
    try:
        return requests.post(SERVICE_URL, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:8080 or refused the connection.")
    except requests.exceptions.Timeout:
        pytest.fail("Service at 127.0.0.1:8080 timed out.")
    except requests.RequestException as exc:
        pytest.fail(f"Request failed: {exc}")


def assert_exact_match(payload):
    expected = oracle_output(payload)
    response = post(payload)
    assert response.status_code == 200, (
        f"Expected 200 OK for {payload!r}, got {response.status_code}"
    )
    assert response.content == expected, (
        f"Output mismatch for {payload!r}: expected exact bytes {expected!r}, "
        f"got {response.content!r}"
    )
    return response


def test_service_is_running():
    response = assert_exact_match(b"ping:pong")
    assert response.status_code == 200


def test_transform_normal_input():
    response = assert_exact_match(b"key1:value1|key2:value2")
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    expected = {"key1": "value1", "key2": "value2"}
    assert data == expected, f"Expected {expected}, got {data}"


def test_transform_drops_empty_values():
    response = assert_exact_match(b"key1:value1|key2:|key3:value3|key4:")
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    expected = {"key1": "value1", "key3": "value3"}
    assert data == expected, f"Expected {expected}, got {data}. Empty values must be dropped."


def test_transform_multiple_colons():
    response = assert_exact_match(b"url:http://example.com|time:12:34:56")
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    expected = {"url": "http://example.com", "time": "12:34:56"}
    assert data == expected, f"Expected {expected}, got {data}"


def token(min_len=1, max_len=18):
    alphabet = string.ascii_letters + string.digits + " _-./"
    return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(max_len - min_len + 1) + min_len))


def test_differential_fuzz_against_legacy_binary():
    nonce = token(8, 14)
    cases = [
        b"",
        b"||||",
        f"{nonce}:value".encode(),
        f"{nonce}:|other:kept".encode(),
        f"{nonce}:first|{nonce}:second".encode(),
        f":{nonce}|empty-key:yes".encode(),
        f"junk||{nonce}:a:b:c|||tail".encode(),
        f"before:yes\nafter:{nonce}".encode(),
        f"before:yes\rafter:{nonce}".encode(),
        (f"long:{nonce}" + "x" * 4300 + "|ignored:value").encode(),
    ]

    for _ in range(64):
        segments = []
        duplicate_key = token()
        for _ in range(secrets.randbelow(10) + 1):
            kind = secrets.randbelow(7)
            if kind == 0:
                segments.append(f"{token()}:{token()}")
            elif kind == 1:
                segments.append(f"{token()}:")
            elif kind == 2:
                segments.append(token())
            elif kind == 3:
                segments.append(f"{token()}:{token()}:{token()}")
            elif kind == 4:
                segments.append(f":{token()}")
            elif kind == 5:
                segments.append(f"{duplicate_key}:{token()}")
            else:
                segments.append("")
        payload = "|".join(segments)
        if secrets.randbelow(3) == 0:
            payload = "|" * (secrets.randbelow(3) + 1) + payload
        if secrets.randbelow(3) == 0:
            payload += "|" * (secrets.randbelow(3) + 1)
        cases.append(payload.encode())

    alphabet = (string.ascii_letters + string.digits + ":| _-./").encode()
    for _ in range(32):
        length = secrets.randbelow(220)
        cases.append(bytes(secrets.choice(alphabet) for _ in range(length)))

    for payload in cases:
        assert_exact_match(payload)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
