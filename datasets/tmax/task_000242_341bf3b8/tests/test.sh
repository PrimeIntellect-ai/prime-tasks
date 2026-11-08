#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import requests
import time
import pytest

def test_api_peaks():
    """Check that the HTTP server returns the correct fitted peak frequencies."""
    url = "http://127.0.0.1:8000/api/peaks"
    max_retries = 10
    success = False
    last_exception = None

    for _ in range(max_retries):
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                data = response.json()

                assert "omega_1" in data, f"Response JSON missing 'omega_1'. Got: {data}"
                assert "omega_2" in data, f"Response JSON missing 'omega_2'. Got: {data}"

                omega_1 = float(data["omega_1"])
                omega_2 = float(data["omega_2"])

                assert abs(omega_1 - 250.0) < 2.0, f"Expected omega_1 near 250.0, got {omega_1}"
                assert abs(omega_2 - 450.0) < 2.0, f"Expected omega_2 near 450.0, got {omega_2}"

                success = True
                break
            else:
                last_exception = f"Server returned status code {response.status_code}"
        except requests.exceptions.RequestException as e:
            last_exception = str(e)
            time.sleep(2)
        except ValueError as e:
            last_exception = f"Failed to parse JSON response: {e}"
            time.sleep(2)

    if not success:
        pytest.fail(f"Failed to get expected JSON from HTTP server on {url}. Last error: {last_exception}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
