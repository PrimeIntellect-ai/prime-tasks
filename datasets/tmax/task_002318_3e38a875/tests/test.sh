#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import requests
import pytest

def test_rotate_endpoint():
    """
    Test that the HTTP server is running on 127.0.0.1:9090,
    responds to GET /rotate, and returns the correct new_key.
    """
    url = "http://127.0.0.1:9090/rotate"
    expected_key = "601a073eecb14ba3613010b9cd1d3b9e4a8ea6c7ccb68d6015b6d773c33dc6f8"

    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the rotate endpoint at {url}. Is the service running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Response text: {response.text}")

    assert "new_key" in data, f"JSON response is missing the 'new_key' field. Data received: {data}"
    assert data["new_key"] == expected_key, f"Incorrect new_key. Expected '{expected_key}', got '{data['new_key']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
