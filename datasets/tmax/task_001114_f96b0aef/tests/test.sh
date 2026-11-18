#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
cleanup() {
    set +e
    if [ -f /app/.verifier_real_sim_binary ]; then
        rm -f /app/sim_binary
        mv /app/.verifier_real_sim_binary /app/sim_binary
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

mv /app/sim_binary /app/.verifier_real_sim_binary
: > /tmp/verifier_invocations
chmod 666 /tmp/verifier_invocations
cat << 'WRAPPER_EOF' > /app/sim_binary
#!/bin/bash
printf '%s\n' "$1" >> /tmp/verifier_invocations
/app/.verifier_real_sim_binary "$@"
rc=$?
if [ "$rc" -eq 0 ] && [ -f sim_output.h5 ]; then
    cp -f sim_output.h5 "/tmp/verifier_capture_${1}.h5"
fi
exit "$rc"
WRAPPER_EOF
chmod 755 /app/sim_binary

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets

import h5py
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8080/run_sim"


def get_expected_sv(N):
    """
    Computes the dominant singular value of the matrix A[i,j] = sin(i*j*0.01)
    using power iteration. Since A is symmetric, the dominant singular value
    is the absolute value of the dominant eigenvalue.
    """
    v = [1.0] * N
    for _ in range(50):
        v_new = [0.0] * N
        for i in range(N):
            for j in range(N):
                v_new[i] += math.sin(i * j * 0.01) * v[j]
        norm = math.sqrt(sum(x * x for x in v_new))
        if norm == 0:
            break
        v = [x / norm for x in v_new]

    num = 0.0
    for i in range(N):
        row_dot = sum(math.sin(i * j * 0.01) * v[j] for j in range(N))
        num += v[i] * row_dot
    return abs(num)


def test_run_sim_endpoint_n100():
    payload = {"mesh_size": 100}
    try:
        response = requests.post(URL, json=payload, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "dominant_singular_value" in data, f"Response JSON missing 'dominant_singular_value' key. Got: {data}"
    actual_sv = data["dominant_singular_value"]
    expected_sv = get_expected_sv(100)
    assert abs(actual_sv - expected_sv) < 1e-2, f"Dominant singular value mismatch for N=100. Expected ~{expected_sv}, got {actual_sv}"


def test_run_sim_endpoint_n50():
    payload = {"mesh_size": 50}
    try:
        response = requests.post(URL, json=payload, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "dominant_singular_value" in data, f"Response JSON missing 'dominant_singular_value' key. Got: {data}"
    actual_sv = data["dominant_singular_value"]
    expected_sv = get_expected_sv(50)
    assert abs(actual_sv - expected_sv) < 1e-2, f"Dominant singular value mismatch for N=50. Expected ~{expected_sv}, got {actual_sv}"


def exercise_and_verify_actual_output(mesh_size):
    capture = f"/tmp/verifier_capture_{mesh_size}.h5"
    if os.path.exists(capture):
        os.unlink(capture)

    with open("/tmp/verifier_invocations", "r") as f:
        before = f.read().splitlines()

    try:
        response = requests.post(URL, json={"mesh_size": mesh_size}, timeout=15)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, response.text
    data = response.json()
    assert "dominant_singular_value" in data
    actual = data["dominant_singular_value"]
    assert isinstance(actual, (int, float)) and math.isfinite(actual)

    with open("/tmp/verifier_invocations", "r") as f:
        after = f.read().splitlines()
    new_invocations = after[len(before):]
    assert str(mesh_size) in new_invocations, f"/app/sim_binary was not executed with mesh_size={mesh_size}"
    assert os.path.isfile(capture), "The simulator's HDF5 output was not produced"

    with h5py.File(capture, "r") as h5:
        assert "/covariance_matrix" in h5
        matrix = h5["/covariance_matrix"][:]
    assert matrix.shape == (mesh_size, mesh_size)

    expected = float(np.linalg.svd(matrix, compute_uv=False)[0])
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), \
        f"Response did not contain the SVD of the generated HDF5 matrix: expected {expected}, got {actual}"


def test_random_simulator_outputs_are_used():
    choices = [n for n in range(32, 81) if n != 50]
    sizes = secrets.SystemRandom().sample(choices, 2)
    for mesh_size in sizes:
        exercise_and_verify_actual_output(mesh_size)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
