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
import json
import math
import os
import stat
import subprocess

import h5py
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8080/features"
AUTH_HEADER = {"X-Auth": "secret-token-123"}
COMPUTE = "/app/ml-server-0.8.2/compute_norm.sh"
SERVE = "/app/ml-server-0.8.2/serve.sh"
H5_PATH = "/home/user/raw_input.h5"


def get_expected_values(path=H5_PATH):
    assert os.path.isfile(path), f"File {path} not found"
    with h5py.File(path, "r") as f:
        data = f["/data/batch_1"][:]
    total_sum = np.sum(data)
    scale_factor = 1.0 / total_sum
    preview = data[:3] * scale_factor
    return round(scale_factor, 6), [round(float(x), 6) for x in preview]


def assert_payload(payload, expected_scale, expected_preview):
    assert isinstance(payload, dict), "JSON response must be an object"
    assert "scale_factor" in payload, "Missing 'scale_factor' in JSON response"
    assert "normalized_preview" in payload, "Missing 'normalized_preview' in JSON response"
    assert isinstance(payload["scale_factor"], (int, float))
    assert math.isfinite(payload["scale_factor"])
    assert abs(payload["scale_factor"] - expected_scale) < 1e-5, \
        f"Expected scale_factor ~{expected_scale}, got {payload['scale_factor']}"

    preview = payload["normalized_preview"]
    assert isinstance(preview, list)
    assert len(preview) == 3, f"Expected 3 items in normalized_preview, got {len(preview)}"
    for i in range(3):
        assert isinstance(preview[i], (int, float)) and math.isfinite(preview[i])
        assert abs(preview[i] - expected_preview[i]) < 1e-5, \
            f"Expected preview[{i}] ~{expected_preview[i]}, got {preview[i]}"


def request_payload():
    try:
        response = requests.get(URL, headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        return response.json(), response.text
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON: {response.text}")


def assert_rejected(headers=None):
    try:
        response = requests.get(URL, headers=headers, timeout=2)
        if response.status_code != 403:
            pytest.fail(f"Expected 403 Forbidden or dropped connection, got {response.status_code}")
    except (requests.exceptions.ConnectionError, requests.exceptions.ReadTimeout):
        pass


def run_compute(path):
    result = subprocess.run(
        [COMPUTE, path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, check=False
    )
    assert result.returncode == 0, f"compute_norm.sh failed: {result.stderr}"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"compute_norm.sh did not emit valid JSON: {result.stdout!r}; stderr={result.stderr!r}")
    return payload, result.stdout


def write_h5(path, data):
    with h5py.File(path, "w") as f:
        f.create_dataset("/data/batch_1", data=np.asarray(data, dtype=np.float64))


def test_required_artifacts_exist_and_are_executable():
    for path in (COMPUTE, SERVE):
        assert os.path.isfile(path), f"Required script {path} is missing"
        assert stat.S_ISREG(os.stat(path).st_mode), f"{path} is not a regular file"
        assert os.access(path, os.X_OK), f"{path} is not executable"


def test_unauthorized_request():
    """Test that requests without the correct X-Auth header are rejected."""
    assert_rejected()


def test_incorrect_nonempty_auth_is_rejected():
    assert_rejected({"X-Auth": "not-secret-token-123"})
    assert_rejected({"X-Auth": "secret-token-123-wrong"})


def test_authorized_request():
    """Test that authorized requests return the correct deterministic JSON."""
    payload, _ = request_payload()
    expected_scale, expected_preview = get_expected_values()
    assert_payload(payload, expected_scale, expected_preview)


def test_authorized_requests_are_repeatable():
    expected_scale, expected_preview = get_expected_values()
    results = []
    for _ in range(10):
        payload, text = request_payload()
        assert_payload(payload, expected_scale, expected_preview)
        results.append((payload, text.strip()))
    assert all(item == results[0] for item in results[1:]), \
        "Authorized requests did not produce identical deterministic results"


def test_compute_norm_processes_its_input(tmp_path):
    custom = tmp_path / "custom_input.h5"
    data = np.linspace(1.0, 2.0, 100, dtype=np.float64)
    write_h5(custom, data)
    expected_scale, expected_preview = get_expected_values(str(custom))

    outputs = []
    for _ in range(8):
        payload, raw = run_compute(str(custom))
        assert_payload(payload, expected_scale, expected_preview)
        outputs.append(raw)
    assert len(set(outputs)) == 1, "compute_norm.sh output changed across repeated runs"


def test_compute_norm_order_sensitive_reduction_is_deterministic(tmp_path):
    custom = tmp_path / "order_sensitive.h5"
    data = np.zeros(100, dtype=np.float64)
    data[0] = 1e16
    data[10] = 1.0
    data[20] = -1e16
    data[30] = data[40] = data[50] = data[60] = 1.0
    data[70] = data[80] = data[90] = 1.0
    write_h5(custom, data)

    outputs = []
    for _ in range(20):
        payload, raw = run_compute(str(custom))
        assert set(payload) >= {"scale_factor", "normalized_preview"}
        assert len(payload["normalized_preview"]) == 3
        # Ordered IEEE accumulation gives 7; an exact/stable summation gives 8.
        assert min(abs(payload["scale_factor"] - 1.0 / 7.0),
                   abs(payload["scale_factor"] - 1.0 / 8.0)) < 1e-5
        outputs.append(raw)
    assert len(set(outputs)) == 1, \
        "Order-sensitive input produced non-deterministic compute_norm.sh output"


def test_server_reprocesses_raw_hdf5_file():
    with open(H5_PATH, "rb") as f:
        original = f.read()
    original_mode = os.stat(H5_PATH).st_mode
    try:
        data = np.linspace(2.0, 4.0, 100, dtype=np.float64)
        write_h5(H5_PATH, data)
        expected_scale, expected_preview = get_expected_values()
        payload, _ = request_payload()
        assert_payload(payload, expected_scale, expected_preview)
    finally:
        with open(H5_PATH, "wb") as f:
            f.write(original)
        os.chmod(H5_PATH, stat.S_IMODE(original_mode))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
