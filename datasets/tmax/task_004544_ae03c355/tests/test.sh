#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os

import numpy as np
import pytest
from scipy.stats import ks_2samp, wasserstein_distance

EXPECTED_FILES = [
    "/home/user/baseline.txt",
    "/home/user/py_float64.txt",
    "/home/user/py_float32.txt",
    "/home/user/metrics.json",
]
TXT_FILES = EXPECTED_FILES[:3]
METRIC_KEYS = {
    "ks_stat_float32",
    "ks_stat_float64",
    "wd_float32",
    "wd_float64",
}


def load_output(path):
    with open(path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 10000, f"File {path} does not have exactly 10,000 lines (found {len(lines)})."
    values = []
    for number, line in enumerate(lines, 1):
        assert line.strip(), f"Blank value on line {number} of {path}."
        try:
            values.append(float(line.strip()))
        except ValueError:
            pytest.fail(f"Non-numeric value on line {number} of {path}.")
    values = np.asarray(values, dtype=np.float64)
    assert np.all(np.isfinite(values)), f"File {path} contains NaN or infinity."
    return values


@pytest.fixture(scope="module")
def results():
    noise_path = "/home/user/noise.bin"
    assert os.path.isfile(noise_path), "The required noise.bin input is missing."
    assert os.path.getsize(noise_path) == 10000000 * 8, "noise.bin has been modified or has the wrong size."

    noise = np.fromfile(noise_path, dtype=np.float64)
    expected_noise = np.random.RandomState(42).randn(10000000).astype(np.float64)
    assert np.array_equal(noise, expected_noise), "noise.bin does not contain the supplied simulation input."
    del expected_noise
    noise = noise.reshape(10000, 1000)

    expected64 = np.full(10000, 2.0, dtype=np.float64)
    for s in range(1000):
        z = noise[:, s]
        expected64 = expected64 - 0.05 * expected64 * expected64 * expected64 + 0.1 * z

    noise32 = noise.astype(np.float32)
    expected32 = np.full(10000, np.float32(2.0), dtype=np.float32)
    c05 = np.float32(0.05)
    c01 = np.float32(0.1)
    for s in range(1000):
        z = noise32[:, s]
        expected32 = expected32 - c05 * expected32 * expected32 * expected32 + c01 * z

    return {
        "baseline": load_output("/home/user/baseline.txt"),
        "float64": load_output("/home/user/py_float64.txt"),
        "float32": load_output("/home/user/py_float32.txt"),
        "expected64": expected64,
        "expected32": expected32.astype(np.float64),
    }


def test_files_exist():
    for path in EXPECTED_FILES:
        assert os.path.isfile(path), f"Expected output file {path} is missing."


def test_output_lengths():
    for path in TXT_FILES:
        if os.path.exists(path):
            with open(path, "r") as f:
                lines = f.read().splitlines()
            assert len(lines) == 10000, f"File {path} does not have exactly 10,000 lines (found {len(lines)})."


def test_simulation_outputs(results):
    assert np.allclose(results["baseline"], results["expected64"], rtol=5e-14, atol=5e-14), \
        "baseline.txt does not contain the results of the supplied C simulation."
    assert np.allclose(results["float64"], results["expected64"], rtol=5e-14, atol=5e-14), \
        "py_float64.txt does not reproduce the float64 simulation."
    assert np.allclose(results["float32"], results["expected32"], rtol=2e-6, atol=2e-6), \
        "py_float32.txt does not reproduce the float32 simulation."


def test_metrics_json(results):
    path = "/home/user/metrics.json"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    for key in METRIC_KEYS:
        assert key in metrics, f"Key '{key}' is missing from metrics.json"
        assert isinstance(metrics[key], (int, float)), f"Value for '{key}' must be a float."
        assert type(metrics[key]) is float, f"Value for '{key}' must be a float."
        assert np.isfinite(metrics[key]), f"Value for '{key}' must be finite."

    recomputed = {
        "ks_stat_float32": float(ks_2samp(results["baseline"], results["float32"]).statistic),
        "ks_stat_float64": float(ks_2samp(results["baseline"], results["float64"]).statistic),
        "wd_float32": float(wasserstein_distance(results["baseline"], results["float32"])),
        "wd_float64": float(wasserstein_distance(results["baseline"], results["float64"])),
    }
    for key, expected in recomputed.items():
        assert np.isclose(metrics[key], expected, rtol=1e-12, atol=1e-12), \
            f"{key} was not calculated from the submitted output files: got {metrics[key]}, expected {expected}."

    # Float64 should be effectively 0
    assert metrics["ks_stat_float64"] < 1e-10, f"ks_stat_float64 is too large: {metrics['ks_stat_float64']}. Expected near 0."
    assert metrics["wd_float64"] < 1e-10, f"wd_float64 is too large: {metrics['wd_float64']}. Expected near 0."

    # Float32 should be strictly greater than 0 due to precision loss
    assert metrics["ks_stat_float32"] > 1e-5, f"ks_stat_float32 is too small: {metrics['ks_stat_float32']}. Expected > 0 due to precision loss."
    assert metrics["wd_float32"] > 1e-5, f"wd_float32 is too small: {metrics['wd_float32']}. Expected > 0 due to precision loss."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
