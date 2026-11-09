#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import requests
import pytest

def test_server_response():
    url = "http://127.0.0.1:8080/path"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_path = [1, 5, 8]
    assert "path" in data, "JSON response is missing the 'path' key"
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
