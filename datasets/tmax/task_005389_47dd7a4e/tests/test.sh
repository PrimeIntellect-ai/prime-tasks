#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tempfile
import pytest
import requests
import numpy as np
import h5py
from scipy.stats import kstest

URL = "http://127.0.0.1:8080/test_svd"


def post_matrix(matrix):
    with tempfile.NamedTemporaryFile(suffix=".h5", delete=False) as tmp:
        tmp_name = tmp.name

    try:
        with h5py.File(tmp_name, "w") as f:
            f.create_dataset("matrix", data=matrix)

        with open(tmp_name, "rb") as f:
            payload = f.read()

        try:
            resp = requests.post(URL, data=payload, timeout=5)
        except requests.exceptions.ConnectionError:
            pytest.fail(f"Could not connect to {URL}. Is the server running?")

        assert resp.status_code == 200, \
            f"Expected status code 200, got {resp.status_code}. Response: {resp.text}"

        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response text: {resp.text}")

        assert "p_value" in data, "Response JSON is missing 'p_value' key."
        assert "reject" in data, "Response JSON is missing 'reject' key."
        assert set(data.keys()) == {"p_value", "reject"}, \
            f"Response JSON must contain exactly p_value and reject, got {set(data.keys())}"
        assert isinstance(data["p_value"], (int, float)), "'p_value' must be a float."
        assert isinstance(data["reject"], bool), "'reject' must be a boolean."
        return data
    finally:
        if os.path.exists(tmp_name):
            os.remove(tmp_name)


def assert_result(matrix):
    singular_values = np.linalg.svd(matrix, compute_uv=False)
    expected_p_value = kstest(singular_values, "uniform").pvalue
    expected_reject = expected_p_value < 0.05
    data = post_matrix(matrix)

    assert abs(data["p_value"] - expected_p_value) < 1e-4, \
        f"Expected p_value ~ {expected_p_value:.5f}, got {data['p_value']}"
    assert data["reject"] == expected_reject, \
        f"Expected reject={expected_reject}, got {data['reject']}"


def test_svd_endpoint():
    # Preserve the original known-value check.
    matrix = np.diag([0.1, 0.5, 0.9])
    singular_values = [0.1, 0.5, 0.9]
    expected_p_value = kstest(singular_values, "uniform").pvalue
    expected_reject = expected_p_value < 0.05
    data = post_matrix(matrix)

    assert abs(data["p_value"] - expected_p_value) < 1e-4, \
        f"Expected p_value ~ {expected_p_value:.5f}, got {data['p_value']}"
    assert data["reject"] == expected_reject, \
        f"Expected reject={expected_reject}, got {data['reject']}"


def test_random_dense_and_rectangular_matrices():
    # Generate unpredictable dense matrices with both accepting and rejecting
    # distributions. Expected values are derived independently from each matrix.
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))

    spectra = []
    for _ in range(2):
        k = int(rng.integers(4, 9))
        regular = (np.arange(k) + 0.5) / k
        regular += rng.uniform(-0.08 / k, 0.08 / k, size=k)
        spectra.append(regular)

        k = int(rng.integers(4, 9))
        spectra.append(rng.uniform(0.005, 0.06, size=k))

    for singular_values in spectra:
        k = len(singular_values)
        m = k + int(rng.integers(1, 4))
        n = k + int(rng.integers(1, 4))
        u, _ = np.linalg.qr(rng.normal(size=(m, k)))
        v, _ = np.linalg.qr(rng.normal(size=(n, k)))
        matrix = u @ np.diag(singular_values) @ v.T
        assert_result(matrix)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
