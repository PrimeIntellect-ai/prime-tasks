#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import socket
import time
from statistics import NormalDist

import pytest
import requests

API_URL = "http://127.0.0.1:9090/api/v1/stats"
TOKEN = "ZETA_99_OMEGA"
CSV_PATH = "/app/sensor_data.csv"
ALPHA = 0.02


def wait_for_port(host, port, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except (ConnectionRefusedError, TimeoutError, OSError):
            time.sleep(0.5)
    return False


def expected_stats(var1, var2):
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.DictReader(f))

    x = [float(row[var1]) for row in rows]
    y = [float(row[var2]) for row in rows]
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    covariance = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y)) / (n - 1)
    sd_x = math.sqrt(sum((a - mean_x) ** 2 for a in x) / (n - 1))
    sd_y = math.sqrt(sum((b - mean_y) ** 2 for b in y) / (n - 1))
    correlation = covariance / (sd_x * sd_y)

    # This is the Fisher transformation used by R's Pearson cor.test CI.
    z = math.atanh(correlation)
    critical = NormalDist().inv_cdf(1 - ALPHA / 2)
    margin = critical / math.sqrt(n - 3)

    return {
        "covariance": round(covariance, 4),
        "correlation": round(correlation, 4),
        "ci_lower": round(math.tanh(z - margin), 4),
        "ci_upper": round(math.tanh(z + margin), 4),
    }


def test_server_listening():
    """Verify that the API server is listening on port 9090."""
    assert wait_for_port("127.0.0.1", 9090), "Server is not listening on 127.0.0.1:9090"


def test_auth_missing():
    """Verify that the endpoint returns 401 when the Authorization header is missing."""
    response = requests.get(f"{API_URL}?var1=Temp&var2=Pressure")
    assert response.status_code == 401, f"Expected 401 Unauthorized when missing token, got {response.status_code}"


def test_auth_invalid():
    """Verify that the endpoint returns 401 when the Authorization header is invalid."""
    headers = {"Authorization": "Bearer INVALID_TOKEN"}
    response = requests.get(f"{API_URL}?var1=Temp&var2=Pressure", headers=headers)
    assert response.status_code == 401, f"Expected 401 Unauthorized when token is invalid, got {response.status_code}"


def test_valid_request_and_math():
    """Verify that a valid request returns 200, correct JSON keys, and accurate math metrics."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    response = requests.get(f"{API_URL}?var1=Temp&var2=Pressure", headers=headers)

    assert response.status_code == 200, f"Expected 200 OK for valid request, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    expected_keys = {"covariance", "correlation", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected keys. Got: {list(data.keys())}"

    # Original expected-value assertions.
    expected_correlation = 0.6489
    expected_covariance = 46.6806
    expected_ci_lower = 0.4578
    expected_ci_upper = 0.7824
    tolerance = 0.005

    assert abs(data["correlation"] - expected_correlation) <= tolerance, f"Correlation {data['correlation']} is not within {tolerance} of {expected_correlation}"
    assert abs(data["covariance"] - expected_covariance) <= tolerance, f"Covariance {data['covariance']} is not within {tolerance} of {expected_covariance}"
    assert abs(data["ci_lower"] - expected_ci_lower) <= tolerance, f"ci_lower {data['ci_lower']} is not within {tolerance} of {expected_ci_lower}"
    assert abs(data["ci_upper"] - expected_ci_upper) <= tolerance, f"ci_upper {data['ci_upper']} is not within {tolerance} of {expected_ci_upper}"


@pytest.mark.parametrize(
    "var1,var2",
    [
        ("Temp", "Vibration"),
        ("Vibration", "Temp"),
        ("Pressure", "Vibration"),
        ("Vibration", "Pressure"),
    ],
)
def test_other_column_pairs_are_computed_from_csv(var1, var2):
    """Exercise every remaining distinct column pair using derived expectations."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    response = requests.get(
        API_URL,
        params={"var1": var1, "var2": var2},
        headers=headers,
        timeout=10,
    )
    assert response.status_code == 200, (
        f"Expected 200 for {var1}/{var2}, got {response.status_code}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response for {var1}/{var2} is not valid JSON")

    expected = expected_stats(var1, var2)
    assert set(data.keys()) == set(expected), f"Unexpected JSON keys for {var1}/{var2}: {list(data.keys())}"

    for key, wanted in expected.items():
        assert type(data[key]) is float, f"{key} for {var1}/{var2} must be a JSON float"
        assert math.isfinite(data[key]), f"{key} for {var1}/{var2} is not finite"
        assert abs(data[key] - wanted) <= 0.000051, (
            f"{key} for {var1}/{var2} was {data[key]}, expected four-decimal value {wanted}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
