#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import requests
import pytest

def test_evidence_extracted():
    """Verify that the evidence archive was extracted."""
    assert os.path.isdir("/app/evidence"), "The /app/evidence directory was not created."
    assert os.path.isfile("/app/evidence/logs/auth.log"), "auth.log is missing from the extracted evidence."
    assert os.path.isfile("/app/evidence/backdoor_bin"), "backdoor_bin is missing from the extracted evidence."

def test_reporting_service():
    """Verify that the reporting service is running and returning the correct JSON."""
    url = "http://127.0.0.1:8443/report"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the reporting service at {url}. Ensure the server is running on port 8443. Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}."

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"The response body is not valid JSON. Response text: {response.text}")

    assert "attacker_ip" in data, "The JSON response is missing the 'attacker_ip' key."
    assert "transcript" in data, "The JSON response is missing the 'transcript' key."

    assert data["attacker_ip"] == "10.5.22.109", f"Incorrect attacker_ip. Expected '10.5.22.109', got '{data['attacker_ip']}'."
    assert data["transcript"] == "crimson butterfly", f"Incorrect transcript. Expected 'crimson butterfly', got '{data['transcript']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
