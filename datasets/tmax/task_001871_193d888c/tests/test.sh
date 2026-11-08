#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import math
import os
import secrets
import struct
import subprocess
import sys
import time

import pytest
import requests

SERVER_URL = "http://127.0.0.1:9090/decode"
AUTH_HEADER = {"Authorization": "Bearer sec-research-agent-2024"}


def wait_for_server():
    timeout = 10
    start_time = time.time()
    while time.time() - start_time < timeout:
        ready = False
        if os.path.exists("/tmp/server_ready.log"):
            with open("/tmp/server_ready.log", "r", errors="replace") as f:
                ready = "READY" in f.read()
        if ready:
            try:
                response = requests.post(
                    SERVER_URL,
                    json={"payload": base64.b64encode(struct.pack("<Q", 1)).decode()},
                    timeout=1,
                )
                if response.status_code == 401:
                    return True
            except requests.RequestException:
                pass
        time.sleep(0.25)
    return False


@pytest.fixture(scope="module", autouse=True)
def setup_server():
    assert wait_for_server(), "READY log is missing or no server is listening on 127.0.0.1:9090"


def post_key(key, suffix=b""):
    payload = struct.pack("<Q", key) + suffix
    encoded = base64.b64encode(payload).decode("ascii")
    return requests.post(SERVER_URL, json={"payload": encoded}, headers=AUTH_HEADER, timeout=10)


def assert_success_response(response, expected_key):
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert set(data) == {"decoded_key", "status"}
    assert data["status"] == "success"
    assert data["decoded_key"] == expected_key


def test_auth_missing():
    payload_data = struct.pack('<Q', 123456789) + b'test_data'
    encoded_payload = base64.b64encode(payload_data).decode('utf-8')
    try:
        response = requests.post(SERVER_URL, json={"payload": encoded_payload}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"


def test_auth_invalid():
    payload_data = struct.pack('<Q', 123456789) + b'test_data'
    encoded_payload = base64.b64encode(payload_data).decode('utf-8')
    headers = {"Authorization": "Bearer invalid-token"}
    try:
        response = requests.post(SERVER_URL, json={"payload": encoded_payload}, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}"


def test_end_to_end_decode():
    test_key = 9876543210987654
    response = post_key(test_key, b'some_encoded_blocks')
    assert_success_response(response, test_key)


def test_custom_activation_is_stable():
    from obfuscation_solver.math_utils import custom_activation

    for x in (0.0, 1.0, 20.0, -20.0, -50.0):
        actual = custom_activation(x)
        expected = math.exp(-x)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-15), (x, actual, expected)


def test_unpack_key_uses_all_64_bits():
    from obfuscation_solver.serializer import unpack_key

    values = [0, 1, (1 << 32) + 7, (1 << 63) + 12345, (1 << 64) - 1]
    for value in values:
        raw = struct.pack("<Q", value) + b"ignored"
        assert unpack_key(raw) == value


def test_decoder_and_exception_path_do_not_deadlock():
    code = r'''
import math
import struct
import threading
from obfuscation_solver import decoder

try:
    decoder.process_block(b"error")
except ValueError:
    pass
else:
    raise AssertionError("error block did not raise")

out = []
t = threading.Thread(target=lambda: out.append(decoder.process_block(b"abcd")))
t.start()
t.join(2)
assert not t.is_alive(), "lock remained held after an exception"
assert len(out) == 1 and math.isclose(out[0], math.exp(-4), rel_tol=1e-12)

key = (1 << 63) + 987654321
payload = struct.pack("<Q", key) + (b"abcd" * 128)
result = decoder.decode_payload(payload)
assert result["key"] == key
assert len(result["results"]) == 128
assert all(math.isclose(v, math.exp(-4), rel_tol=1e-12) for v in result["results"])
'''
    completed = subprocess.run(
        [sys.executable, "-c", code],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr


def test_endpoint_decodes_varied_unpredictable_keys():
    keys = [0, (1 << 32) + 19, (1 << 63) + 29, (1 << 64) - 1]
    keys.extend(secrets.randbits(64) for _ in range(4))
    for i, key in enumerate(keys):
        response = post_key(key, (b"block-%02d" % i) * 3)
        assert_success_response(response, key)


def test_service_source_invokes_package_decoder():
    candidates = []
    for root in ("/app", "/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {"__pycache__", ".git", "site-packages"}]
            for name in filenames:
                path = os.path.join(dirpath, name)
                if not name.endswith(".py") or path in {__file__, "/app/obfuscation_solver/decoder.py"}:
                    continue
                try:
                    text = open(path, "r", encoding="utf-8").read()
                except (OSError, UnicodeError):
                    continue
                if "obfuscation_solver" in text and "decode_payload" in text:
                    candidates.append(path)
    assert candidates, "No service source imports and invokes obfuscation_solver.decoder.decode_payload"

    valid = False
    for path in candidates:
        try:
            tree = ast.parse(open(path, "r", encoding="utf-8").read())
        except (OSError, SyntaxError, UnicodeError):
            continue
        imported = any(
            (isinstance(n, ast.Import) and any(a.name.startswith("obfuscation_solver") for a in n.names))
            or (isinstance(n, ast.ImportFrom) and (n.module or "").startswith("obfuscation_solver"))
            for n in ast.walk(tree)
        )
        called = any(
            isinstance(n, ast.Call)
            and (
                (isinstance(n.func, ast.Name) and n.func.id == "decode_payload")
                or (isinstance(n.func, ast.Attribute) and n.func.attr == "decode_payload")
            )
            for n in ast.walk(tree)
        )
        if imported and called:
            valid = True
            break
    assert valid, "Service code does not call the package's decode_payload function"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
