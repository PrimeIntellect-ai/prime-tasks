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
import stat
import json
import base64
import hmac
import hashlib
import secrets
import importlib.metadata
import requests
import pytest

BASE_URL = "http://127.0.0.1:8000/data"
VENDORED_ROOT = os.path.realpath("/app/vendored/pyjwt_custom-1.0.0")

def encode_part(value):
    return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode().rstrip("=")

def make_token(header, payload, secret=None, signature=None):
    header_b64 = encode_part(header)
    payload_b64 = encode_part(payload)
    msg = f"{header_b64}.{payload_b64}"
    if signature is None and secret is not None:
        digest = hmac.new(secret.encode(), msg.encode(), hashlib.sha256).digest()
        signature = base64.urlsafe_b64encode(digest).decode().rstrip("=")
    if signature is None:
        signature = ""
    return f"{msg}.{signature}"

def get_secret():
    with open("/home/user/keys/secret.key", "r") as f:
        return f.read().strip()

def request_with_token(token):
    try:
        return requests.get(BASE_URL, headers={"Authorization": f"Bearer {token}"}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

def test_secret_key_permissions():
    path = "/home/user/keys/secret.key"
    assert os.path.isfile(path), f"Secret key file missing: {path}"
    st = os.stat(path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Secret key permissions are {oct(perms)}, expected 0o400. File permissions policy not enforced."

def test_patched_package_is_installed_from_vendored_source():
    dist = importlib.metadata.distribution("pyjwt_custom")
    assert dist.version == "1.0.0"

    import pyjwt_custom
    import pyjwt_custom.decoder as decoder

    package_file = os.path.realpath(pyjwt_custom.__file__)
    decoder_file = os.path.realpath(decoder.__file__)
    assert os.path.commonpath([package_file, VENDORED_ROOT]) == VENDORED_ROOT, \
        f"Installed pyjwt_custom is not loaded from the vendored package: {package_file}"
    assert os.path.commonpath([decoder_file, VENDORED_ROOT]) == VENDORED_ROOT, \
        f"Installed decoder is not loaded from the vendored package: {decoder_file}"
    assert os.path.isfile("/app/vendored/pyjwt_custom-1.0.0/pyjwt_custom/decoder.py")

def test_installed_library_signature_and_none_behavior():
    import pyjwt_custom

    secret = secrets.token_hex(24)
    payload = {"user": secrets.token_hex(12), "nonce": secrets.token_hex(16)}

    valid = make_token({"alg": "HS256", "typ": "JWT"}, payload, secret=secret)
    assert pyjwt_custom.decode(valid, secret) == payload

    bad_signature = make_token(
        {"alg": "HS256", "typ": "JWT"}, payload,
        signature=base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")
    )
    with pytest.raises(pyjwt_custom.InvalidTokenError):
        pyjwt_custom.decode(bad_signature, secret)

    for algorithm in ("none", "NONE", "NoNe", None):
        forged = make_token({"alg": algorithm, "typ": "JWT"}, payload)
        with pytest.raises(pyjwt_custom.InvalidTokenError):
            pyjwt_custom.decode(forged, secret)

def test_server_no_auth():
    try:
        resp = requests.get(BASE_URL, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert resp.status_code == 401, f"Expected HTTP 401 for request without Authorization header, got {resp.status_code}"

def test_server_alg_none():
    header = {"alg": "none", "typ": "JWT"}
    payload = {"user": "test"}
    token = make_token(header, payload)
    resp = request_with_token(token)
    assert resp.status_code == 401, f"Expected HTTP 401 for token with alg='none', got {resp.status_code}. The vulnerability bypass is likely still active."

def test_server_valid_token():
    path = "/home/user/keys/secret.key"
    assert os.path.isfile(path), f"Secret key file missing: {path}"
    secret = get_secret()
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"user": "test"}
    token = make_token(header, payload, secret=secret)
    resp = request_with_token(token)
    assert resp.status_code == 200, f"Expected HTTP 200 for valid signed token, got {resp.status_code}"

def test_server_randomized_signature_validation_and_response_body():
    secret = get_secret()
    payload = {"user": secrets.token_hex(12), "nonce": secrets.token_hex(20)}
    header = {"alg": "HS256", "typ": "JWT"}

    valid = make_token(header, payload, secret=secret)
    valid_resp = request_with_token(valid)
    assert valid_resp.status_code == 200, f"Expected HTTP 200 for randomized valid token, got {valid_resp.status_code}"
    assert valid_resp.json() == {"data": "secret data", "payload": payload}

    wrong_secret = secrets.token_hex(32)
    invalid = make_token(header, payload, secret=wrong_secret)
    invalid_resp = request_with_token(invalid)
    assert invalid_resp.status_code == 401, f"Expected HTTP 401 for invalid signature, got {invalid_resp.status_code}"
    assert invalid_resp.json().get("error") == "Invalid token"

    for algorithm in ("none", "NONE", "NoNe"):
        forged = make_token({"alg": algorithm, "typ": "JWT"}, payload)
        forged_resp = request_with_token(forged)
        assert forged_resp.status_code == 401, f"Expected HTTP 401 for alg={algorithm!r}, got {forged_resp.status_code}"
        assert forged_resp.json().get("error") == "Invalid token"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
