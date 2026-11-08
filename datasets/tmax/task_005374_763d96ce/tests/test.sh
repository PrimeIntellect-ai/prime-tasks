#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import socket
import pytest
import requests

def test_http_csp_check():
    """Verify the HTTP service on port 8080 returns the correct CSP header."""
    url = "http://127.0.0.1:8080/csp-check"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service on port 8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    csp_header = response.headers.get("Content-Security-Policy")
    assert csp_header is not None, "Missing Content-Security-Policy header in response"

    expected_csp = "default-src 'none'; frame-ancestors 'none';"
    assert csp_header == expected_csp, f"Expected CSP header '{expected_csp}', got '{csp_header}'"

def test_tcp_rotation_oracle_correct_password():
    """Verify the TCP service on port 8081 returns the rotated credential for the correct password."""
    host = '127.0.0.1'
    port = 8081
    password = b"reddragonfly4092\n"
    expected_response = b"ROTATED_CRED_9921\n"

    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(password)
            response = s.recv(1024)
    except Exception as e:
        pytest.fail(f"Failed to communicate with TCP service on port 8081: {e}")

    assert response == expected_response, f"Expected '{expected_response.decode()}', got '{response.decode(errors='replace')}'"

def test_tcp_rotation_oracle_wrong_password():
    """Verify the TCP service on port 8081 returns DENIED for an incorrect password."""
    host = '127.0.0.1'
    port = 8081
    password = b"wrongpassword\n"
    expected_response = b"DENIED\n"

    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(password)
            response = s.recv(1024)
    except Exception as e:
        pytest.fail(f"Failed to communicate with TCP service on port 8081: {e}")

    assert response == expected_response, f"Expected '{expected_response.decode()}', got '{response.decode(errors='replace')}'"

def test_rotation_setup_log():
    """Verify that /home/user/rotation_setup.log exists and contains the cracked legacy password."""
    log_path = "/home/user/rotation_setup.log"
    assert os.path.isfile(log_path), f"File not found: {log_path}"

    with open(log_path, "r") as f:
        first_line = f.readline().strip()

    expected_password = "reddragonfly4092"
    assert first_line == expected_password, f"Expected first line of {log_path} to be '{expected_password}', got '{first_line}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
