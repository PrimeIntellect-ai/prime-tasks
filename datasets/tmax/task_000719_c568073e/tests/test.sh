#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import requests
import pytest

def test_server_response():
    file_path = '/app/voicemail.wav'
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    # Compute SHA-256 hash of the file
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    expected_hash = sha256_hash.hexdigest()

    # Make request to the server
    url = "http://127.0.0.1:8080/"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Error: {e}")

    # Check status code
    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}."

    # Check Content-Security-Policy header
    csp_header = response.headers.get('Content-Security-Policy')
    assert csp_header is not None, "Content-Security-Policy header is missing from the response."
    assert csp_header.strip() == "default-src 'none'", f"Expected Content-Security-Policy to be \"default-src 'none'\", but got \"{csp_header}\"."

    # Check body contains the correct hash
    actual_body = response.text.strip()
    assert expected_hash in actual_body, f"The response body does not contain the expected SHA-256 hash. Expected: {expected_hash}, Got: {actual_body}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
