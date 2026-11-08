#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/jwt_scanner.py"
API_JWS_PATH = "/app/pyjwt/jwt/api_jws.py"
SECRET = "vulnerability-scan-2024"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(payload, algorithm="HS256", secret=SECRET):
    header = {"alg": algorithm, "typ": "JWT"}
    encoded_header = b64url(json.dumps(header, separators=(",", ":")).encode())
    encoded_payload = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{encoded_header}.{encoded_payload}".encode()
    if algorithm == "none":
        signature = ""
    else:
        signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    return f"{encoded_header}.{encoded_payload}.{signature}"


def test_pyjwt_perturbation_removed():
    """Ensure the deliberate backdoor in the vendored pyjwt package has been removed."""
    assert os.path.isfile(API_JWS_PATH), f"{API_JWS_PATH} is missing"
    with open(API_JWS_PATH, "r") as f:
        content = f.read()

    assert 'header.get("alg") == "none"' not in content.replace("'", '"'), \
        "The backdoor perturbation in api_jws.py is still present."


def test_vendored_pyjwt_signature_behavior():
    """Exercise the vendored package and verify that signatures and algorithms are enforced."""
    nonce = secrets.token_hex(16)
    payload = {
        "nonce": nonce,
        "csp_directive": "default-src 'self'",
        "b64_payload": base64.b64encode(b"safe").decode(),
    }
    good = make_token(payload)
    unsigned = make_token(payload, algorithm="none", secret="")
    invalid = make_token(payload, secret="incorrect-secret")

    code = r'''
import os
import sys
sys.path.insert(0, "/app/pyjwt")
import jwt

assert os.path.realpath(jwt.__file__).startswith("/app/pyjwt/"), jwt.__file__
good, unsigned, invalid, secret, nonce = sys.argv[1:]
decoded = jwt.decode(good, secret, algorithms=["HS256"])
assert decoded["nonce"] == nonce
for token in (unsigned, invalid):
    try:
        jwt.decode(token, secret, algorithms=["HS256"])
    except Exception:
        pass
    else:
        raise AssertionError("Vendored pyjwt accepted an unsigned or invalidly signed token")
'''
    result = subprocess.run(
        ["python3", "-c", code, good, unsigned, invalid, SECRET, nonce],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_scanner_script_exists():
    """Ensure the student created the scanner script."""
    assert os.path.isfile(SCRIPT_PATH), f"Scanner script {SCRIPT_PATH} is missing"


def test_adversarial_corpus():
    """Test the scanner against freshly generated clean and evil tokens."""
    assert os.path.isfile(SCRIPT_PATH), f"Scanner script {SCRIPT_PATH} is missing"

    clean_tokens = []
    evil_tokens = []

    for i in range(50):
        nonce = secrets.token_hex(16)
        clean_tokens.append(make_token({
            "csp_directive": "default-src 'self'",
            "b64_payload": base64.b64encode(f"safe data {i} {nonce}".encode()).decode(),
        }))

    for i in range(50):
        nonce = secrets.token_hex(16)
        if i < 15:
            payload = {
                "nonce": nonce,
                "csp_directive": "default-src 'self'",
                "b64_payload": base64.b64encode(b"safe").decode(),
            }
            evil_tokens.append(make_token(payload, algorithm="none", secret=""))
        elif i < 30:
            payload = {
                "nonce": nonce,
                "csp_directive": "default-src 'self' 'unsafe-inline'",
                "b64_payload": base64.b64encode(b"safe").decode(),
            }
            evil_tokens.append(make_token(payload))
        else:
            payload = {
                "nonce": nonce,
                "csp_directive": "default-src 'self'",
                "b64_payload": base64.b64encode(
                    f"<script>alert('{nonce}')</script>".encode()
                ).decode(),
            }
            evil_tokens.append(make_token(payload))

    evil_bypassed = []
    for index, token in enumerate(evil_tokens):
        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--token", token],
            capture_output=True,
        )
        if result.returncode == 0:
            evil_bypassed.append(str(index))

    clean_modified = []
    for index, token in enumerate(clean_tokens):
        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--token", token],
            capture_output=True,
        )
        if result.returncode != 0:
            clean_modified.append(str(index))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_tokens)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {len(clean_tokens)} clean modified: {', '.join(clean_modified)}"
        )

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
