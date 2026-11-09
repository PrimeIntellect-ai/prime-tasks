#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os

import numpy as np
import pytest
import requests
from scipy.io import wavfile
from scipy.signal import stft
from scipy.stats import wasserstein_distance

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer ds-secret-token-42"}


def compute_expected_metrics():
    sample_rate, samples = wavfile.read("/app/system_noise.wav")
    _, _, zxx = stft(samples, fs=sample_rate, nperseg=256, noverlap=128)
    spectrogram = np.abs(zxx)

    u, singular_values, vh = np.linalg.svd(spectrogram, full_matrices=False)
    approximation = (
        u[:, :5]
        @ np.diag(singular_values[:5])
        @ vh[:5, :]
    )

    midpoint = approximation.shape[1] // 2
    p = approximation[:, :midpoint].mean(axis=1) + 1e-9
    q = approximation[:, midpoint:].mean(axis=1) + 1e-9
    p = p / p.sum()
    q = q / q.sum()
    kl_divergence = np.sum(p * np.log(p / q))

    return float(singular_values[0]), float(kl_divergence)


def get_json(response, endpoint):
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {endpoint} is not valid JSON. Response: {response.text}")


def test_metrics_no_auth():
    """Verify that /metrics endpoint requires authorization."""
    try:
        response = requests.get(f"{BASE_URL}/metrics", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /metrics: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without auth token, got {response.status_code}"


def test_metrics_with_auth():
    """Verify that /metrics returns values computed from the supplied WAV file."""
    try:
        response = requests.get(f"{BASE_URL}/metrics", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /metrics: {e}")

    assert response.status_code == 200, f"Expected 200 OK with auth token, got {response.status_code}. Response: {response.text}"
    data = get_json(response, "/metrics")

    assert "singular_value_1" in data, "Missing 'singular_value_1' in JSON response"
    assert "kl_divergence" in data, "Missing 'kl_divergence' in JSON response"
    assert isinstance(data["singular_value_1"], (int, float)), "singular_value_1 must be a number"
    assert isinstance(data["kl_divergence"], (int, float)), "kl_divergence must be a number"
    assert data["singular_value_1"] > 0, f"singular_value_1 should be > 0, got {data['singular_value_1']}"
    assert data["kl_divergence"] > 0, f"kl_divergence should be > 0, got {data['kl_divergence']}"

    expected_sv1, expected_kl = compute_expected_metrics()
    assert math.isfinite(float(data["singular_value_1"]))
    assert math.isfinite(float(data["kl_divergence"]))
    assert np.isclose(float(data["singular_value_1"]), expected_sv1, rtol=1e-5, atol=1e-7), (
        f"Incorrect largest singular value: expected {expected_sv1}, got {data['singular_value_1']}"
    )
    assert np.isclose(float(data["kl_divergence"]), expected_kl, rtol=1e-5, atol=1e-8), (
        f"Incorrect KL divergence: expected {expected_kl}, got {data['kl_divergence']}"
    )


def test_compare_no_auth():
    """Verify that /compare endpoint requires authorization."""
    payload = {"reference": [1, 2, 3], "test": [2, 3, 4]}
    try:
        response = requests.post(f"{BASE_URL}/compare", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /compare: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without auth token, got {response.status_code}"


@pytest.mark.parametrize("endpoint,method", [("/metrics", "get"), ("/compare", "post")])
@pytest.mark.parametrize("bad_header", [
    {"Authorization": "Bearer wrong-token"},
    {"Authorization": "ds-secret-token-42"},
    {"Authorization": "bearer ds-secret-token-42"},
])
def test_invalid_authorization_tokens(endpoint, method, bad_header):
    payload = {"reference": [0.0, 2.0], "test": [5.0, 7.0]}
    if method == "get":
        response = requests.get(f"{BASE_URL}{endpoint}", headers=bad_header, timeout=5)
    else:
        response = requests.post(f"{BASE_URL}{endpoint}", headers=bad_header, json=payload, timeout=5)
    assert response.status_code == 401, (
        f"Expected 401 for invalid authorization on {endpoint}, got {response.status_code}"
    )


def assert_compare_result(reference, test):
    payload = {"reference": reference, "test": test}
    try:
        response = requests.post(f"{BASE_URL}/compare", headers=AUTH_HEADER, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /compare: {e}")

    assert response.status_code == 200, f"Expected 200 OK with auth token, got {response.status_code}. Response: {response.text}"
    data = get_json(response, "/compare")
    assert "wasserstein_distance" in data, "Missing 'wasserstein_distance' in JSON response"

    wd = data["wasserstein_distance"]
    assert isinstance(wd, (int, float)), "wasserstein_distance must be a number"
    assert math.isfinite(float(wd)), "wasserstein_distance must be finite"

    expected = float(wasserstein_distance(reference, test))
    assert np.isclose(float(wd), expected, rtol=1e-7, atol=1e-8), (
        f"Expected wasserstein_distance {expected}, got {wd}"
    )
    return float(wd)


def test_compare_with_auth():
    """Retain the original fixed comparison assertion."""
    wd = assert_compare_result([1, 2, 3], [2, 3, 4])
    assert abs(wd - 1.0) < 1e-5, f"Expected wasserstein_distance to be approx 1.0, got {wd}"


def test_compare_varied_runtime_inputs():
    """Exercise the endpoint on independently derived, non-fixed inputs."""
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    cases = [
        ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0]),
        (rng.normal(-3.0, 0.7, 11).tolist(), rng.normal(4.0, 1.8, 17).tolist()),
        (rng.uniform(-20.0, 20.0, 23).tolist(), rng.exponential(2.5, 8).tolist()),
    ]
    for reference, test in cases:
        assert_compare_result(reference, test)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
