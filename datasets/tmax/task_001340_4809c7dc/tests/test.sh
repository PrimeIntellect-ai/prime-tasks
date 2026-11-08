#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import pytest
import requests
import socket

HTTP_URL = "http://127.0.0.1:8080/"
TCP_HOST = "127.0.0.1"
TCP_PORT = 8081
TIMEOUT = 3.0

PASSPHRASE = "black hat magic"
EXPECTED_HASH = "a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3"
EXPECTED_PAYLOAD = "admin' UNION SELECT NULL,NULL,NULL--\n"

def test_http_honeypot_correct_passphrase():
    """Test the HTTP honeypot with the correct passphrase."""
    headers = {"X-Passphrase": PASSPHRASE}
    try:
        response = requests.get(HTTP_URL, headers=headers, timeout=TIMEOUT)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP honeypot at {HTTP_URL}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response body: {response.text}"
    assert response.text.strip() == EXPECTED_HASH, f"Expected response body to be the original hash '{EXPECTED_HASH}', but got '{response.text}'"

def test_http_honeypot_wrong_passphrase():
    """Test the HTTP honeypot with an incorrect passphrase."""
    headers = {"X-Passphrase": "wrong passphrase"}
    try:
        response = requests.get(HTTP_URL, headers=headers, timeout=TIMEOUT)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP honeypot at {HTTP_URL}: {e}")

    assert response.status_code == 403, f"Expected status code 403 for incorrect passphrase, got {response.status_code}. Response body: {response.text}"

def test_http_honeypot_missing_passphrase():
    """Test the HTTP honeypot without the passphrase header."""
    try:
        response = requests.get(HTTP_URL, timeout=TIMEOUT)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP honeypot at {HTTP_URL}: {e}")

    assert response.status_code == 403, f"Expected status code 403 for missing passphrase header, got {response.status_code}. Response body: {response.text}"

def test_tcp_honeypot_payload():
    """Test the TCP honeypot to ensure it returns the correct payload."""
    try:
        with socket.create_connection((TCP_HOST, TCP_PORT), timeout=TIMEOUT) as s:
            s.sendall(b"SEND_PAYLOAD\n")

            # Read response
            response_data = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                response_data += chunk
                # Stop if we see a newline, as per the spec
                if b"\n" in chunk:
                    break

            response_text = response_data.decode('utf-8', errors='replace')

            assert response_text == EXPECTED_PAYLOAD, f"Expected TCP response to be exactly '{EXPECTED_PAYLOAD.strip()}\\n', but got '{response_text}'"

    except ConnectionRefusedError:
        pytest.fail(f"Connection refused to TCP honeypot at {TCP_HOST}:{TCP_PORT}. Ensure the service is running and bound to the correct port.")
    except socket.timeout:
        pytest.fail(f"Timeout while connecting to or reading from TCP honeypot at {TCP_HOST}:{TCP_PORT}.")
    except Exception as e:
        pytest.fail(f"Unexpected error while communicating with TCP honeypot: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
