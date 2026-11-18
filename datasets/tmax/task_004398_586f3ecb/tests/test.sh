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
import subprocess
import tempfile
import hmac
import hashlib
import requests
import json
import pytest
import secrets
import string

URL = "http://127.0.0.1:8080/verify"
HEADERS = {"Content-Type": "application/json"}


def get_elf_salt():
    try:
        with tempfile.NamedTemporaryFile() as tmp:
            subprocess.run(
                ['objcopy', '-O', 'binary', '--only-section=.secret_salt', '/app/legacy_crypto.so', tmp.name],
                check=True,
                capture_output=True
            )
            with open(tmp.name, 'rb') as f:
                salt_bytes = f.read()
                return salt_bytes.replace(b'\x00', b'').decode('utf-8')
    except Exception:
        return "L3g4cy_S@1t_88"


def hmac_key():
    master_key = "M4ST3R_K3Y_2024_R0T4T10N"
    return f"{master_key}:{get_elf_salt()}".encode('utf-8')


def make_token(payload):
    payload_bytes = payload.encode('utf-8')
    payload_hex = payload_bytes.hex()
    signature = hmac.new(hmac_key(), payload_bytes, hashlib.sha256).hexdigest()
    return f"{payload_hex}.{signature}"


def post_token(token):
    try:
        return requests.post(URL, json={"token": token}, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the validation service at {URL}: {e}")


def assert_success(token):
    response = post_token(token)
    assert response.status_code == 200, (
        f"Expected HTTP 200 for valid token, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        body = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response for valid token was not valid JSON: {response.text}")
    assert body.get("status") == "success", (
        f"Expected status 'success' for valid token, got: {body}"
    )


def assert_failed(token):
    response = post_token(token)
    assert response.status_code == 401, (
        f"Expected HTTP 401 for invalid token, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        body = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response for invalid token was not valid JSON: {response.text}")
    assert body.get("status") == "failed", (
        f"Expected status 'failed' for invalid token, got: {body}"
    )


def test_verify_endpoint_original_cases():
    payload = "user=admin&role=superuser"
    payload_hex = payload.encode('utf-8').hex()
    valid_hmac = hmac.new(hmac_key(), payload.encode('utf-8'), hashlib.sha256).hexdigest()
    valid_token = f"{payload_hex}.{valid_hmac}"
    invalid_token = f"{payload_hex}.deadbeefdeadbeef"

    assert_success(valid_token)
    assert_failed(invalid_token)


def test_runtime_generated_tokens_and_forgery_rejection():
    alphabet = string.ascii_letters + string.digits

    for index in range(8):
        nonce = ''.join(secrets.choice(alphabet) for _ in range(30))
        payload = f"user={nonce}&role=role{index}&counter={secrets.randbelow(10**9)}"
        token = make_token(payload)
        payload_hex, signature = token.split('.')

        # Every valid case is generated only when verification runs, so a server
        # must generally decode the payload and calculate its HMAC.
        assert_success(token)

        replacement = '0' if signature[0] != '0' else '1'
        assert_failed(f"{payload_hex}.{replacement}{signature[1:]}")

        replacement = '0' if payload_hex[-1] != '0' else '1'
        altered_payload_hex = payload_hex[:-1] + replacement
        assert_failed(f"{altered_payload_hex}.{signature}")


def test_malformed_tokens_are_rejected():
    malformed = [
        "",
        "no-dot-separator",
        "." + "0" * 64,
        "0." + "0" * 64,
        "zz." + "0" * 64,
        "616263.not-hex",
        "616263." + "0" * 63,
        "616263." + "0" * 65,
        "616263." + "0" * 64 + ".extra",
    ]
    for token in malformed:
        assert_failed(token)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
