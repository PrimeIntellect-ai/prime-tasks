#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import urllib.request
import json
import pytest

def test_services_running_and_data_endpoint():
    """
    Test that Nginx is running on port 8080, properly proxying to Flask,
    and Flask is successfully fetching data from Redis.
    """
    url = "http://localhost:8080/data"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
            assert "signal" in data, "JSON response missing 'signal' key"
            assert isinstance(data["signal"], list), "'signal' is not a list"
            assert len(data["signal"]) == 1024, f"Expected signal length 1024, got {len(data['signal'])}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url} or fetch data: {e}. Are the services started and configured correctly?")

def test_periodicity_file_metric():
    """
    Test that the periodicity.txt file exists and contains a value within the acceptable tolerance.
    """
    target_file = "/home/user/periodicity.txt"
    assert os.path.exists(target_file), f"Output file {target_file} is missing."

    with open(target_file, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {target_file} could not be parsed as a float. Content: '{content}'")

    target_value = 0.42
    error = abs(val - target_value)
    threshold = 0.05

    assert error <= threshold, (
        f"Periodicity parameter d is outside acceptable tolerance. "
        f"Measured value: {val}, Target: {target_value}, Error: {error:.4f}, Threshold: {threshold}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
