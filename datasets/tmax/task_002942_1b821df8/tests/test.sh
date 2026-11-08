#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import requests
import pytest

def test_reporting_service():
    """Verify the reporting service is running and returns the correct JSON report."""
    url = "http://127.0.0.1:9090/report"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the reporting service at {url}. Is the server running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Body: {response.text}")

    expected_key = "5ca83f91b20d44e71a8f"
    expected_script = "backup_sys.sh"
    expected_cwe = "CWE-78"

    assert "key" in data, "JSON response is missing the 'key' field."
    assert data["key"] == expected_key, f"Incorrect key. Expected '{expected_key}', got '{data['key']}'"

    assert "script" in data, "JSON response is missing the 'script' field."
    assert data["script"] == expected_script, f"Incorrect script. Expected '{expected_script}', got '{data['script']}'"

    assert "cwe" in data, "JSON response is missing the 'cwe' field."
    assert data["cwe"] == expected_cwe, f"Incorrect CWE. Expected '{expected_cwe}', got '{data['cwe']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
