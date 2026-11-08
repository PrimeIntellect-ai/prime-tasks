#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import requests
import math
import pytest

URL = "http://127.0.0.1:9090/api/analysis"
HEADERS = {"X-Researcher-Token": "alpha-bravo-charlie"}

def test_unauthorized_request():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code in [401, 403], f"Expected HTTP 401 or 403 for unauthorized request, got {response.status_code}"

def test_authorized_request_and_payload():
    try:
        response = requests.get(URL, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK for authorized request, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "pearson_corr" in data, "Missing 'pearson_corr' in JSON response"
    assert "cov_matrix" in data, "Missing 'cov_matrix' in JSON response"

    expected_pearson = 0.9829
    expected_cov = [
        [13.7000, 15.0000],
        [15.0000, 17.0000]
    ]

    assert math.isclose(float(data["pearson_corr"]), expected_pearson, abs_tol=1e-4), \
        f"Expected pearson_corr around {expected_pearson}, got {data['pearson_corr']}"

    cov_matrix = data["cov_matrix"]
    assert isinstance(cov_matrix, list) and len(cov_matrix) == 2, "Covariance matrix must be a 2x2 list"
    assert isinstance(cov_matrix[0], list) and len(cov_matrix[0]) == 2, "Covariance matrix must be a 2x2 list"
    assert isinstance(cov_matrix[1], list) and len(cov_matrix[1]) == 2, "Covariance matrix must be a 2x2 list"

    for i in range(2):
        for j in range(2):
            assert math.isclose(float(cov_matrix[i][j]), expected_cov[i][j], abs_tol=1e-4), \
                f"Mismatch in cov_matrix[{i}][{j}]: expected {expected_cov[i][j]}, got {cov_matrix[i][j]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
