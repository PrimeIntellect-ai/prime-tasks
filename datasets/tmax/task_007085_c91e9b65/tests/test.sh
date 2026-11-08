#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import subprocess

import numpy as np
import pytest

SO_FILE = "/home/user/src/libintegrator.so"
PY_FILE = "/home/user/prepare_data.py"
JSON_FILE = "/home/user/regression_metrics.json"
GOLDEN_FILE = "/home/user/data/golden_trajectory.csv"


def reference_integrate(x0, v0, dt, steps):
    out_x = np.empty(steps, dtype=np.float64)
    out_v = np.empty(steps, dtype=np.float64)
    x = float(x0)
    v = float(v0)
    for i in range(steps):
        out_x[i] = x
        out_v[i] = v

        x1, v1 = x, v
        a1 = -math.sin(x1) - 0.2 * v1

        x2 = x + 0.5 * dt * v1
        v2 = v + 0.5 * dt * a1
        a2 = -math.sin(x2) - 0.2 * v2

        x3 = x + 0.5 * dt * v2
        v3 = v + 0.5 * dt * a2
        a3 = -math.sin(x3) - 0.2 * v3

        x4 = x + dt * v3
        v4 = v + dt * a3
        a4 = -math.sin(x4) - 0.2 * v4

        x += (dt / 6.0) * (v1 + 2 * v2 + 2 * v3 + v4)
        v += (dt / 6.0) * (a1 + 2 * a2 + 2 * a3 + a4)
    return out_x, out_v


def load_and_integrate(x0, v0, dt, steps):
    lib = ctypes.CDLL(SO_FILE)
    lib.integrate.argtypes = [
        ctypes.c_double,
        ctypes.c_double,
        ctypes.c_double,
        ctypes.c_int,
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
    ]
    lib.integrate.restype = None
    out_x = np.zeros(steps, dtype=np.float64)
    out_v = np.zeros(steps, dtype=np.float64)
    lib.integrate(x0, v0, dt, steps, out_x, out_v)
    return out_x, out_v


@pytest.fixture(scope="session", autouse=True)
def execute_submission_and_compute_expected():
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} is missing. Did you compile the C code?"
    assert os.path.isfile(PY_FILE), f"Python script {PY_FILE} is missing."

    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)
    result = subprocess.run(
        ["python3", PY_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{PY_FILE} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_FILE), f"Output JSON {JSON_FILE} is missing. Did you save the regression metrics?"

    # Exercise the submitted shared library on independently derived cases.
    for args in [(0.37, -0.21, 0.017, 37), (-2.1, 0.8, 0.031, 23)]:
        actual_x, actual_v = load_and_integrate(*args)
        expected_x, expected_v = reference_integrate(*args)
        np.testing.assert_allclose(actual_x, expected_x, rtol=1e-12, atol=2e-13)
        np.testing.assert_allclose(actual_v, expected_v, rtol=1e-12, atol=2e-13)

    x, v = load_and_integrate(3.0, 0.0, 0.05, 1000)
    ref_x, ref_v = reference_integrate(3.0, 0.0, 0.05, 1000)
    np.testing.assert_allclose(x, ref_x, rtol=1e-12, atol=2e-13)
    np.testing.assert_allclose(v, ref_v, rtol=1e-12, atol=2e-13)
    a = np.gradient(v, 0.05, edge_order=2)

    golden = np.genfromtxt(GOLDEN_FILE, delimiter=",", names=True)
    assert golden.dtype.names == ("x", "v", "a")
    assert golden.shape == (1000,)

    # Ensure the regression input itself was not replaced by the submission.
    rng = np.random.RandomState(42)
    pristine_x = ref_x + rng.normal(0, 1e-5, 1000)
    pristine_v = ref_v + rng.normal(0, 1e-5, 1000)
    pristine_a = np.gradient(ref_v, 0.05, edge_order=2) + rng.normal(0, 1e-5, 1000)
    np.testing.assert_allclose(golden["x"], pristine_x, rtol=0, atol=5e-15)
    np.testing.assert_allclose(golden["v"], pristine_v, rtol=0, atol=5e-15)
    np.testing.assert_allclose(golden["a"], pristine_a, rtol=0, atol=5e-15)

    return {
        "mse_x": float(np.mean((x - golden["x"]) ** 2)),
        "mse_v": float(np.mean((v - golden["v"]) ** 2)),
        "mse_a": float(np.mean((a - golden["a"]) ** 2)),
    }


def test_shared_library_exists():
    """Check if the C source code was compiled into a shared library."""
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} is missing. Did you compile the C code?"


def test_python_script_exists():
    """Check if the preparation script exists."""
    assert os.path.isfile(PY_FILE), f"Python script {PY_FILE} is missing."


def test_json_output_exists():
    """Check if the regression metrics JSON file was created."""
    assert os.path.isfile(JSON_FILE), f"Output JSON {JSON_FILE} is missing. Did you save the regression metrics?"


def test_json_contents_and_mse_values(execute_submission_and_compute_expected):
    """Validate the structure and independently recomputed values of the metrics JSON."""
    with open(JSON_FILE, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_FILE} does not contain valid JSON.")

    expected_keys = ["mse_x", "mse_v", "mse_a"]
    for key in expected_keys:
        assert key in metrics, f"Key '{key}' is missing in the JSON output."
        assert isinstance(metrics[key], float), f"The value for '{key}' must be a float."
    assert set(metrics) == set(expected_keys), "The JSON output must contain exactly the required three keys."

    mse_x = metrics["mse_x"]
    mse_v = metrics["mse_v"]
    mse_a = metrics["mse_a"]
    assert 9e-11 < mse_x < 1.1e-10, f"mse_x value {mse_x} is out of expected range (9e-11 to 1.1e-10). Check your integration or MSE calculation."
    assert 9e-11 < mse_v < 1.1e-10, f"mse_v value {mse_v} is out of expected range (9e-11 to 1.1e-10). Check your integration or MSE calculation."
    assert 9e-11 < mse_a < 1.1e-10, f"mse_a value {mse_a} is out of expected range (9e-11 to 1.1e-10). Check your acceleration derivative or MSE calculation."

    for key, expected in execute_submission_and_compute_expected.items():
        assert math.isclose(metrics[key], expected, rel_tol=1e-7, abs_tol=1e-16), (
            f"{key}={metrics[key]} does not match the independently recomputed value {expected}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
