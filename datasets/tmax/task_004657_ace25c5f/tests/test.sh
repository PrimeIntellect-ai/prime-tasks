#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import random

import pytest
import requests

URL = "http://127.0.0.1:8080/fit"
AUTH_HEADER = {"Authorization": "Bearer LabSecret99"}

# Generate fresh, independent parameter tuples and noise for every verifier run.
# The ranges cover the same problem domain as the original fixed cases.
rng = random.SystemRandom()
CASES = [
    (
        rng.uniform(2.5, 5.0),
        rng.uniform(0.8, 1.5),
        rng.uniform(2.5, 4.0),
    )
    for _ in range(2)
]

def generate_signal(A, D, F, noise_std=0.01):
    data = []
    for i in range(100):
        t = i * 0.01
        val = A * math.exp(-t / D) * math.cos(2 * math.pi * F * t)
        noise = rng.gauss(0, noise_std)
        data.append(val + noise)
    return data

def test_auth_missing():
    data = {"data": [0.0] * 100}
    try:
        response = requests.post(URL, json=data, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

def test_auth_invalid():
    data = {"data": [0.0] * 100}
    headers = {"Authorization": "Bearer WrongSecret"}
    try:
        response = requests.post(URL, json=data, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid auth header, got {response.status_code}"

@pytest.mark.parametrize("true_A,true_D,true_F", CASES, ids=["random-case-1", "random-case-2"])
def test_fit_endpoint(true_A, true_D, true_F):
    signal = generate_signal(true_A, true_D, true_F, noise_std=0.05)
    payload = {"data": signal}

    try:
        response = requests.post(URL, json=payload, headers=AUTH_HEADER, timeout=15)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        result = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    for key in ["amplitude", "decay", "frequency"]:
        assert key in result, f"Missing '{key}' in response JSON"

    est_A = result["amplitude"]
    est_D = result["decay"]
    est_F = result["frequency"]

    # Check within the original 5% tolerance.
    assert abs(est_A - true_A) / true_A <= 0.05, f"Amplitude {est_A} not within 5% of {true_A}"
    assert abs(est_D - true_D) / true_D <= 0.05, f"Decay {est_D} not within 5% of {true_D}"
    assert abs(est_F - true_F) / true_F <= 0.05, f"Frequency {est_F} not within 5% of {true_F}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
