#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import pytest
import requests
import math

def test_model_endpoint():
    url = "http://127.0.0.1:8000/model"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "frequencies" in data, "Response JSON missing 'frequencies' key"
    assert "laplacian" in data, "Response JSON missing 'laplacian' key"

    freqs = data["frequencies"]
    assert isinstance(freqs, list), "'frequencies' should be a list"
    assert freqs == [440, 554, 659], f"Expected frequencies [440, 554, 659], got {freqs}"

    L = data["laplacian"]
    assert isinstance(L, list), "'laplacian' should be a list"
    assert len(L) == 4, "'laplacian' should be a 4x4 matrix"
    for row in L:
        assert isinstance(row, list), "Each row in 'laplacian' should be a list"
        assert len(row) == 4, "Each row in 'laplacian' should have 4 elements"

    # Check symmetric
    for i in range(4):
        for j in range(4):
            assert abs(L[i][j] - L[j][i]) < 1e-4, f"Laplacian is not symmetric at ({i}, {j})"

    # Check row sums
    for i in range(4):
        row_sum = sum(L[i])
        assert abs(row_sum) < 1e-4, f"Row {i} sum is {row_sum}, expected 0"

    # Check off-diagonals <= 1e-4
    for i in range(4):
        for j in range(4):
            if i != j:
                assert L[i][j] <= 1e-4, f"Off-diagonal element L[{i}][{j}] = {L[i][j]} is not <= 0"

    # Compute eigenvalues using numpy
    try:
        import numpy as np
    except ImportError:
        pytest.fail("numpy is required to verify eigenvalues but is not installed.")

    L_np = np.array(L)
    eigenvalues = np.linalg.eigvalsh(L_np)
    eigenvalues = np.sort(eigenvalues)

    expected_eigvals = np.array([0.0, 4.40, 5.54, 6.59])

    for i in range(4):
        assert abs(eigenvalues[i] - expected_eigvals[i]) < 0.05, \
            f"Eigenvalue {i} is {eigenvalues[i]}, expected {expected_eigvals[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
