#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import requests
import socket
import struct
import pytest

def test_validator_service_directly():
    """
    Connect to the validator service on port 9090 directly and send a correctly formatted payload.
    This verifies that the socat/validator service is running and properly accepts binary input.
    """
    magic = 0x424D4F42
    version = 8492
    is_debug = 0
    # Expected format: <I I B 3x
    payload = struct.pack("<IIB3x", magic, version, is_debug)

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(('127.0.0.1', 9090))
        s.sendall(payload)
        resp = s.recv(1024)
        s.close()
    except ConnectionRefusedError:
        pytest.fail("Validator service is not listening on 127.0.0.1:9090.")
    except Exception as e:
        pytest.fail(f"Error communicating with validator service on port 9090: {e}")

    assert b"OK" in resp, f"Validator service did not return 'OK'. Actual response: {resp!r}"

def test_api_gateway_validation():
    """
    Connect to the Flask API gateway on port 8080 and send a JSON payload.
    This verifies that the API is running, correctly parses the JSON, serializes it,
    communicates with the validator, and returns the expected result.
    """
    url = "http://127.0.0.1:8080/validate"
    payload = {"version_code": 8492, "is_debug": 0}
    headers = {"Content-Type": "application/json"}

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("API gateway is not listening on 127.0.0.1:8080.")
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to communicate with the API gateway: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API response is not valid JSON. Response text: {response.text}")

    assert data.get("status") == "VALID", f"Expected response JSON to contain 'status': 'VALID'. Actual response: {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
