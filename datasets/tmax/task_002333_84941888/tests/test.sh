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
import socket
import ssl
import subprocess

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:8443/audit-report"
LOCALHOST_URL = "https://localhost:8443/audit-report"
AUTH_TOKEN = "SecT0k3n_99xA"
REDACT_USER = "admin_charlie"
CERT_PATH = "/home/user/certs/cert.pem"
KEY_PATH = "/home/user/certs/key.pem"
LOG_PATH = "/home/user/audit_logs.txt"


def run_openssl(*args, input_data=None):
    return subprocess.run(
        ["openssl", *args],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def test_certs_exist():
    """Test that the required certificate and key exist and form a localhost self-signed pair."""
    assert os.path.isfile(CERT_PATH), f"Certificate file {CERT_PATH} is missing."
    assert os.path.isfile(KEY_PATH), f"Private key file {KEY_PATH} is missing."

    cert_info = run_openssl("x509", "-in", CERT_PATH, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253").decode()
    fields = dict(line.split("=", 1) for line in cert_info.strip().splitlines())
    assert fields.get("subject") == fields.get("issuer"), "Certificate is not self-signed."
    run_openssl("verify", "-CAfile", CERT_PATH, CERT_PATH)

    cert_pub_pem = run_openssl("x509", "-in", CERT_PATH, "-pubkey", "-noout")
    cert_pub_der = run_openssl("pkey", "-pubin", "-outform", "DER", input_data=cert_pub_pem)
    key_pub_der = run_openssl("pkey", "-in", KEY_PATH, "-pubout", "-outform", "DER")
    assert cert_pub_der == key_pub_der, "Private key does not match the certificate."

    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    response = requests.get(LOCALHOST_URL, headers=headers, verify=CERT_PATH, timeout=5)
    assert response.status_code == 200, "The certificate is not valid for localhost."

    context = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as sock:
        with context.wrap_socket(sock, server_hostname="localhost") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    with open(CERT_PATH, encoding="ascii") as cert_file:
        required_der = ssl.PEM_cert_to_DER_cert(cert_file.read())
    assert served_der == required_der, "The server is not using /home/user/certs/cert.pem."


def test_unauthenticated_request():
    """Test that a request without the correct Authorization header returns 401."""
    try:
        response = requests.get(URL, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for unauthenticated request, got {response.status_code}."


def test_incorrect_bearer_token():
    """Test that an incorrect Bearer token is rejected."""
    try:
        response = requests.get(
            URL,
            headers={"Authorization": "Bearer definitely-wrong-token"},
            verify=False,
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for an incorrect Bearer token, got {response.status_code}."


def test_authenticated_request_and_redaction():
    """Test the authenticated response, exact redacted log, headers, and status."""
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}

    try:
        response = requests.get(URL, headers=headers, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for authenticated request, got {response.status_code}."

    csp_header = response.headers.get("Content-Security-Policy")
    expected_csp = "default-src 'self'; frame-ancestors 'none';"
    assert csp_header == expected_csp, f"Expected CSP header '{expected_csp}', got '{csp_header}'."
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain"), "Expected Content-Type text/plain."

    with open(LOG_PATH, encoding="utf-8") as log_file:
        expected_body = log_file.read().replace(REDACT_USER, "[REDACTED]")

    body = response.text
    assert body == expected_body, "Response body is not the complete redacted audit log."
    assert REDACT_USER not in body, f"Found unredacted username '{REDACT_USER}' in the response body."
    assert "[REDACTED]" in body, "Expected to find '[REDACTED]' in the response body."
    assert "user_alice" in body, "Expected content 'user_alice' missing from the response body."
    assert "LOGIN SUCCESS" in body, "Expected content 'LOGIN SUCCESS' missing from the response body."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
