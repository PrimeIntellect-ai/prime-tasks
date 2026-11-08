#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import pytest
import requests
import numpy as np

URL = "http://127.0.0.1:8000/stats"
API_KEY = "model-fitter-88"

def get_expected_values():
    # Reconstruct the measurements
    np.random.seed(123)
    measurements = np.random.uniform(-5, 5, 50)

    def f(x):
        return x**3 - 2*x**2 + x

    h = 1e-3
    derivatives = (f(measurements + h) - f(measurements - h)) / (2 * h)

    mean_deriv = np.mean(derivatives)

    np.random.seed(42)
    n_iterations = 1000
    bootstrap_means = np.empty(n_iterations)
    for i in range(n_iterations):
        sample = np.random.choice(derivatives, size=len(derivatives), replace=True)
        bootstrap_means[i] = np.mean(sample)

    ci_lower = np.percentile(bootstrap_means, 2.5)
    ci_upper = np.percentile(bootstrap_means, 97.5)

    return {
        "mean_derivative": round(mean_deriv, 4),
        "ci_95_lower": round(ci_lower, 4),
        "ci_95_upper": round(ci_upper, 4)
    }

def test_unauthorized_missing_header():
    """Test that a request without the API key header returns a 401 status code."""
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing header, got {response.status_code}"

def test_unauthorized_wrong_header():
    """Test that a request with an incorrect API key header returns a 401 status code."""
    headers = {"X-API-Key": "wrong-key-123"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong header, got {response.status_code}"

def test_authorized_correct_response():
    """Test that a request with the correct API key returns the expected JSON data."""
    headers = {"X-API-Key": API_KEY}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    expected = get_expected_values()

    for key in expected:
        assert key in data, f"Missing key '{key}' in JSON response. Got: {data}"

        # Check against expected values, allowing for minor floating point differences just in case,
        # but expecting exactly 4 decimal places rounding as instructed.
        assert data[key] == pytest.approx(expected[key], abs=1e-4), \
            f"Value for '{key}' does not match. Expected {expected[key]}, got {data[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
