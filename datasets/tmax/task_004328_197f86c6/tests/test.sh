#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ssl
import json
import base64
import hmac
import hashlib
import secrets
import socket
import py_compile
from pathlib import Path

import pytest
import requests
import urllib3
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec, dsa, ed25519, ed448, padding

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:8443/audit/log"
LOG_PATH = Path("/home/user/audit.log")
SECRET_PATH = Path("/home/user/jwt_secret.txt")
CERT_PATH = Path("/home/user/cert.pem")
KEY_PATH = Path("/home/user/key.pem")
SERVER_PATH = Path("/home/user/server.py")


def base64url_encode(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def create_jwt(payload, secret, alg="HS256", header_extra=None):
    header = {"typ": "JWT", "alg": alg}
    if header_extra:
        header.update(header_extra)
    encoded_header = base64url_encode(json.dumps(header, separators=(",", ":")))
    encoded_payload = base64url_encode(json.dumps(payload, separators=(",", ":")))
    message = f"{encoded_header}.{encoded_payload}"
    if alg == "none":
        return f"{message}."
    if alg == "HS256":
        signature = hmac.new(secret.encode("utf-8"), message.encode("ascii"), hashlib.sha256).digest()
        return f"{message}.{base64url_encode(signature)}"
    raise ValueError("Unsupported algorithm")


def post(body, token=None):
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    return requests.post(URL, json=body, headers=headers, verify=False, timeout=5)


def log_bytes():
    return LOG_PATH.read_bytes() if LOG_PATH.exists() else b""


def assert_new_log_entry(before, username, event, cc_number):
    after = log_bytes()
    expected = f"[{username}] {event} - ****-****-****-{cc_number[-4:]}".encode()
    added = after[len(before):]
    assert after.startswith(before), "Existing audit log content was overwritten."
    assert expected in added, f"New audit log content is incorrect: {added!r}"
    assert cc_number.encode() not in added, "Unredacted credit-card number was written to the audit log."


def test_secret_file():
    assert SECRET_PATH.exists(), f"Secret file {SECRET_PATH} does not exist."
    secret = SECRET_PATH.read_text().strip()
    assert secret == "4928", f"Secret file contains incorrect secret: {secret}"


def test_server_artifact():
    assert SERVER_PATH.is_file(), f"Server artifact {SERVER_PATH} does not exist or is not a regular file."
    py_compile.compile(str(SERVER_PATH), doraise=True)


def test_certificates_exist_and_are_in_use():
    assert CERT_PATH.exists(), f"Certificate file {CERT_PATH} does not exist."
    assert KEY_PATH.exists(), f"Key file {KEY_PATH} does not exist."

    cert = x509.load_pem_x509_certificate(CERT_PATH.read_bytes())
    key = serialization.load_pem_private_key(KEY_PATH.read_bytes(), password=None)
    cert_pub = cert.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    key_pub = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    assert cert_pub == key_pub, "The private key does not match the certificate."
    assert cert.subject == cert.issuer, "The certificate is not self-signed."

    public_key = cert.public_key()
    if isinstance(public_key, rsa.RSAPublicKey):
        public_key.verify(cert.signature, cert.tbs_certificate_bytes, padding.PKCS1v15(), cert.signature_hash_algorithm)
    elif isinstance(public_key, ec.EllipticCurvePublicKey):
        public_key.verify(cert.signature, cert.tbs_certificate_bytes, ec.ECDSA(cert.signature_hash_algorithm))
    elif isinstance(public_key, dsa.DSAPublicKey):
        public_key.verify(cert.signature, cert.tbs_certificate_bytes, cert.signature_hash_algorithm)
    elif isinstance(public_key, (ed25519.Ed25519PublicKey, ed448.Ed448PublicKey)):
        public_key.verify(cert.signature, cert.tbs_certificate_bytes)
    else:
        pytest.fail("Unsupported certificate public-key type.")

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="127.0.0.1") as tls:
            served_der = tls.getpeercert(binary_form=True)
    assert served_der == cert.public_bytes(serialization.Encoding.DER), \
        "The HTTPS service is not using /home/user/cert.pem."


def test_original_fixed_endpoint_cases():
    payload1 = {"username": "admin", "cc_number": "1111222233334444", "event": "login"}
    jwt1 = create_jwt({}, "4928", alg="HS256")
    try:
        resp1 = post(payload1, jwt1)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {URL}: {exc}")
    assert resp1.status_code == 200, f"Expected HTTP 200 for valid JWT, got {resp1.status_code}"
    assert LOG_PATH.exists(), f"Audit log {LOG_PATH} was not created."
    logs = LOG_PATH.read_text()
    assert "[admin] login - ****-****-****-4444" in logs, "Audit log missing or incorrect for valid request."

    payload2 = {"username": "hacker", "cc_number": "9999888877776666", "event": "data_dump"}
    jwt2 = create_jwt({}, "4928", alg="none")
    resp2 = post(payload2, jwt2)
    assert resp2.status_code == 200, f"Expected HTTP 200 for alg=none JWT, got {resp2.status_code}"
    logs = LOG_PATH.read_text()
    assert "[hacker] data_dump - ****-****-****-6666" in logs, "Audit log missing or incorrect for alg=none request."

    payload3 = {"username": "thief", "cc_number": "1234123412341234", "event": "steal"}
    jwt3 = create_jwt({}, "0000", alg="HS256")
    resp3 = post(payload3, jwt3)
    assert resp3.status_code == 401, f"Expected HTTP 401 for invalid JWT signature, got {resp3.status_code}"
    logs = LOG_PATH.read_text()
    assert "[thief]" not in logs, "Audit log should not contain entry for unauthorized request."


def test_randomized_authentication_and_redaction():
    secret = SECRET_PATH.read_text().strip()

    for index in range(6):
        username = f"user_{secrets.token_hex(9)}"
        event = f"event_{secrets.token_hex(11)}"
        cc_number = "".join(str(secrets.randbelow(10)) for _ in range(16))
        body = {"username": username, "cc_number": cc_number, "event": event}
        jwt_payload = {
            "sub": secrets.token_hex(13),
            "nonce": secrets.token_urlsafe(17),
            "round": index,
        }

        before = log_bytes()
        response = post(body, create_jwt(jwt_payload, secret, "HS256", {"kid": secrets.token_hex(5)}))
        assert response.status_code == 200, f"Random valid HS256 token was rejected with {response.status_code}."
        assert_new_log_entry(before, username, event, cc_number)

        username_none = f"none_{secrets.token_hex(9)}"
        event_none = f"event_{secrets.token_hex(11)}"
        cc_none = "".join(str(secrets.randbelow(10)) for _ in range(16))
        body_none = {"username": username_none, "cc_number": cc_none, "event": event_none}
        before = log_bytes()
        response = post(body_none, create_jwt(jwt_payload, secrets.token_hex(8), "none", {"kid": secrets.token_hex(5)}))
        assert response.status_code == 200, f"Random alg=none token was rejected with {response.status_code}."
        assert_new_log_entry(before, username_none, event_none, cc_none)

        bad_username = f"bad_{secrets.token_hex(10)}"
        bad_body = {
            "username": bad_username,
            "cc_number": "".join(str(secrets.randbelow(10)) for _ in range(16)),
            "event": f"event_{secrets.token_hex(10)}",
        }
        wrong_secret = secrets.token_hex(20)
        before = log_bytes()
        response = post(bad_body, create_jwt(jwt_payload, wrong_secret, "HS256", {"kid": secrets.token_hex(5)}))
        assert response.status_code == 401, f"Invalid HS256 signature returned {response.status_code}, not 401."
        assert log_bytes() == before, "An invalid-signature request modified the audit log."
        assert f"[{bad_username}]" not in LOG_PATH.read_text(), "Unauthorized request was logged."


def test_missing_bearer_token_is_unauthorized():
    body = {
        "username": f"missing_{secrets.token_hex(8)}",
        "cc_number": "".join(str(secrets.randbelow(10)) for _ in range(16)),
        "event": f"event_{secrets.token_hex(8)}",
    }
    before = log_bytes()
    response = post(body, None)
    assert response.status_code == 401, f"Request without a bearer token returned {response.status_code}, not 401."
    assert log_bytes() == before, "A request without authentication modified the audit log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
