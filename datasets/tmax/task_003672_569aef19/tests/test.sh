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
import hmac
import json
import os
import secrets
import socket
import subprocess
import time

import pytest
import requests

MASTER_KEY = "".join(["S3cr3t", "C0mpl1anc3", "K3y!"])


def b64url_encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_decode(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def make_hs256_token(user, key=MASTER_KEY):
    header = b64url_encode(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url_encode(json.dumps({"user": user}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}"
    signature = hmac.new(key.encode(), signing_input.encode("ascii"), hashlib.sha256).digest()
    return f"{signing_input}.{b64url_encode(signature)}"


def assert_independently_valid_token(token, expected_user):
    assert isinstance(token, str), f"Expected token to be a string, got {type(token)!r}"
    parts = token.split(".")
    assert len(parts) == 3, f"Expected a three-part JWT, got: {token!r}"

    try:
        header = json.loads(b64url_decode(parts[0]).decode("utf-8"))
        payload = json.loads(b64url_decode(parts[1]).decode("utf-8"))
        signature = b64url_decode(parts[2])
    except Exception as exc:
        pytest.fail(f"Token is not a valid encoded JWT: {exc}")

    assert header.get("alg") == "HS256", f"Expected JWT alg HS256, got: {header}"
    assert payload.get("user") == expected_user, f"JWT user claim is incorrect: {payload}"
    expected_signature = hmac.new(
        MASTER_KEY.encode(), f"{parts[0]}.{parts[1]}".encode("ascii"), hashlib.sha256
    ).digest()
    assert hmac.compare_digest(signature, expected_signature), "JWT signature does not match the extracted master key"


def test_pyjwt_fixed():
    """Verify that the tampered PyJWT HMAC verification has been fixed."""
    algorithms_file = "/app/PyJWT-2.8.0/jwt/algorithms.py"
    assert os.path.isfile(algorithms_file), f"File {algorithms_file} is missing."
    with open(algorithms_file, "r") as f:
        content = f.read()
    assert "return False # TAMPERED" not in content, "The PyJWT library still contains the tampered code."
    assert "hmac.compare_digest" in content, "The PyJWT library does not contain the correct hmac.compare_digest fix."


def test_pyjwt_installed_and_verification_works():
    """Verify the repaired editable package is installed and its HMAC verifier works."""
    script = r'''
import hashlib
import os
import jwt
from jwt.algorithms import HMACAlgorithm

source_root = os.path.realpath("/app/PyJWT-2.8.0")
module_path = os.path.realpath(jwt.__file__)
assert os.path.commonpath([source_root, module_path]) == source_root, (source_root, module_path)

alg = HMACAlgorithm(hashlib.sha256)
key = alg.prepare_key(b"independent-test-key")
message = b"message-checked-by-verifier"
signature = alg.sign(message, key)
assert alg.verify(message, key, signature) is True
assert alg.verify(message + b"-changed", key, signature) is False

encoded = jwt.encode({"user": "package_test"}, "independent-test-key", algorithm="HS256")
assert jwt.decode(encoded, "independent-test-key", algorithms=["HS256"])["user"] == "package_test"
try:
    jwt.decode(encoded, "wrong-key", algorithms=["HS256"])
except jwt.InvalidSignatureError:
    pass
else:
    raise AssertionError("Installed PyJWT accepted an invalid HMAC signature")
'''
    result = subprocess.run(["python3", "-c", script], text=True, capture_output=True)
    assert result.returncode == 0, f"Repaired PyJWT is not correctly installed or functional:\n{result.stdout}\n{result.stderr}"


def test_http_service_token_and_validate():
    """Verify the HTTP service generates and validates tokens correctly."""
    url_token = "http://127.0.0.1:8080/token"
    url_validate = "http://127.0.0.1:8080/validate"

    try:
        resp = requests.post(url_token, json={"user": "compliance_auditor"}, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url_token}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK from /token, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /token, got: {resp.text}")

    assert "token" in data, f"Response from /token does not contain 'token' key. Got: {data}"
    token = data["token"]
    assert_independently_valid_token(token, "compliance_auditor")

    try:
        resp2 = requests.post(url_validate, json={"token": token}, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url_validate}: {e}")

    assert resp2.status_code == 200, f"Expected 200 OK from /validate, got {resp2.status_code}. Response: {resp2.text}"

    try:
        data2 = resp2.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /validate, got: {resp2.text}")

    assert data2.get("valid") is True, f"Expected 'valid': true in response, got: {data2}"
    assert data2.get("user") == "compliance_auditor", f"Expected 'user': 'compliance_auditor' in response, got: {data2}"


def test_http_service_random_users_and_independent_tokens():
    """Exercise unpredictable users and independently generated HS256 tokens."""
    url_token = "http://127.0.0.1:8080/token"
    url_validate = "http://127.0.0.1:8080/validate"

    for _ in range(3):
        user = f"audit_{secrets.token_hex(12)}"
        resp = requests.post(url_token, json={"user": user}, timeout=2)
        assert resp.status_code == 200, f"Expected 200 from /token, got {resp.status_code}: {resp.text}"
        try:
            token = resp.json()["token"]
        except (ValueError, KeyError, TypeError) as exc:
            pytest.fail(f"Invalid /token JSON response: {resp.text}; {exc}")
        assert_independently_valid_token(token, user)

    independent_user = f"independent_{secrets.token_hex(12)}"
    independent_token = make_hs256_token(independent_user)
    resp = requests.post(url_validate, json={"token": independent_token}, timeout=2)
    assert resp.status_code == 200, f"Service rejected an independently signed valid token: {resp.status_code} {resp.text}"
    data = resp.json()
    assert data.get("valid") is True, f"Expected valid=true, got: {data}"
    assert data.get("user") == independent_user, f"Expected user {independent_user!r}, got: {data}"

    wrong_key_token = make_hs256_token(f"wrong_{secrets.token_hex(8)}", key="definitely-not-the-master-key")
    resp = requests.post(url_validate, json={"token": wrong_key_token}, timeout=2)
    assert resp.status_code == 401, f"Expected 401 for a correctly formed token signed with the wrong key, got {resp.status_code}: {resp.text}"


def test_http_service_invalid_token():
    """Verify the HTTP service rejects invalid tokens with a 401 status."""
    url_validate = "http://127.0.0.1:8080/validate"
    try:
        resp = requests.post(url_validate, json={"token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.token"}, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url_validate}: {e}")

    assert resp.status_code == 401, f"Expected 401 Unauthorized from /validate for invalid token, got {resp.status_code}. Response: {resp.text}"


def send_tcp_message(message):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(("127.0.0.1", 8081))
            s.sendall((message + "\n").encode())
    except Exception as e:
        pytest.fail(f"Failed to connect and send data to TCP service on port 8081: {e}")


def test_tcp_service_audit_log():
    """Verify the TCP service correctly hashes messages and appends to the audit log."""
    message = "SYSTEM_STARTUP_EVENT"
    expected_hash = hashlib.sha256(message.encode()).hexdigest()
    expected_log_entry = f"[{expected_hash}] {message}\n"

    send_tcp_message(message)
    time.sleep(0.5)

    log_file = "/home/user/audit.log"
    assert os.path.isfile(log_file), f"Audit log file {log_file} does not exist. Ensure the TCP service creates it."

    with open(log_file, "r") as f:
        content = f.read()

    assert expected_log_entry in content, f"Expected log entry '{expected_log_entry.strip()}' not found in {log_file}. Content was: {content}"


def test_tcp_service_random_messages():
    """Verify SHA-256 logging for multiple unpredictable messages."""
    log_file = "/home/user/audit.log"
    before_size = os.path.getsize(log_file) if os.path.isfile(log_file) else 0
    messages = [
        f"LOGIN {secrets.token_hex(13)}",
        f"policy-update-{secrets.token_hex(17)}",
        f"event with spaces {secrets.token_hex(11)}",
    ]
    expected = [f"[{hashlib.sha256(message.encode()).hexdigest()}] {message}\n" for message in messages]

    for message in messages:
        send_tcp_message(message)

    deadline = time.time() + 3
    appended = ""
    while time.time() < deadline:
        if os.path.isfile(log_file):
            with open(log_file, "r") as f:
                f.seek(before_size)
                appended = f.read()
            if all(entry in appended for entry in expected):
                break
        time.sleep(0.1)

    for entry in expected:
        assert entry in appended, f"Expected randomized log entry {entry.strip()!r} in newly appended log data. Got: {appended!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
