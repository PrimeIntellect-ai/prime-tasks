#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"

def test_alpha_gcode_served_correctly():
    url = f"{BASE_URL}/artifacts/alpha.gcode"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}. Is the server running? Error: {e}")

    assert response.status_code == 200, f"Expected 200 OK for {url}, got {response.status_code}. Response: {response.text[:100]}"
    expected_content = b"; BEGIN GCODE\nG1 X10 Y20\nM104 S200\n"
    assert response.content == expected_content, "Content for alpha.gcode does not match the expected decrypted plaintext."

def test_beta_gcode_served_correctly():
    url = f"{BASE_URL}/artifacts/beta.gcode"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}. Is the server running? Error: {e}")

    assert response.status_code == 200, f"Expected 200 OK for {url}, got {response.status_code}. Response: {response.text[:100]}"
    expected_content = b"; BEGIN GCODE\nG28\nG1 Z10\n"
    assert response.content == expected_content, "Content for beta.gcode does not match the expected decrypted plaintext."

def test_gamma_gcode_returns_404():
    url = f"{BASE_URL}/artifacts/gamma.gcode"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}. Is the server running? Error: {e}")

    assert response.status_code == 404, f"Expected 404 Not Found for {url} (corrupt zlib archive), got {response.status_code}."

def test_delta_gcode_returns_404():
    url = f"{BASE_URL}/artifacts/delta.gcode"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}. Is the server running? Error: {e}")

    assert response.status_code == 404, f"Expected 404 Not Found for {url} (missing '; BEGIN GCODE' header), got {response.status_code}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
