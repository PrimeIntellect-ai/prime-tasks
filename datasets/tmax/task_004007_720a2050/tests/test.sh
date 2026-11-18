#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import subprocess
import textwrap

import numpy as np
import pytest

SCRIPT = "/home/user/benchmark.py"
LOG = "/home/user/experiment_log.json"
MODEL_DIR = "/home/user/models"
TRUE_MODEL = os.path.join(MODEL_DIR, "ground_truth.py")
APPROX_MODEL = os.path.join(MODEL_DIR, "fast_approx.py")
TRUE_CALLS = "/tmp/benchmark_true_calls.jsonl"
APPROX_CALLS = "/tmp/benchmark_approx_calls.jsonl"


@pytest.fixture(scope="session", autouse=True)
def execute_benchmark_with_instrumented_models():
    assert os.path.isfile(SCRIPT), "/home/user/benchmark.py script is missing."

    with open(TRUE_MODEL, "rb") as f:
        original_true = f.read()
    with open(APPROX_MODEL, "rb") as f:
        original_approx = f.read()

    delta = random.SystemRandom().uniform(1.0e-8, 8.0e-8)
    true_delay = random.SystemRandom().uniform(0.020, 0.030)
    approx_delay = random.SystemRandom().uniform(0.005, 0.010)

    true_wrapper = f'''
import json
import time
import numpy as np

_EXPECTED = np.linspace(0.0, 100.0, 1000000, dtype=np.float64)
_LOG = {TRUE_CALLS!r}
_DELAY = {true_delay!r}

def compute_true(x: np.ndarray) -> np.ndarray:
    start = time.perf_counter()
    assert isinstance(x, np.ndarray)
    assert x.shape == (1000000,)
    assert x.dtype == np.float64
    assert np.array_equal(x, _EXPECTED)
    time.sleep(_DELAY)
    result = np.exp(-x / 10.0) * np.sin(x) * np.cos(2 * x)
    elapsed = time.perf_counter() - start
    with open(_LOG, "a") as f:
        f.write(json.dumps({{"elapsed": elapsed}}) + "\\n")
    return result
'''

    approx_wrapper = f'''
import json
import time
import numpy as np

_EXPECTED = np.linspace(0.0, 100.0, 1000000, dtype=np.float64)
_LOG = {APPROX_CALLS!r}
_DELAY = {approx_delay!r}
_DELTA = {delta!r}

def compute_approx(x: np.ndarray) -> np.ndarray:
    start = time.perf_counter()
    assert isinstance(x, np.ndarray)
    assert x.shape == (1000000,)
    assert x.dtype == np.float64
    assert np.array_equal(x, _EXPECTED)
    time.sleep(_DELAY)
    x32 = x.astype(np.float32)
    result = np.exp(-x32 / 10.0) * np.sin(x32) * np.cos(2 * x32)
    result = result.astype(np.float64) + _DELTA * (x / 100.0)
    elapsed = time.perf_counter() - start
    with open(_LOG, "a") as f:
        f.write(json.dumps({{"elapsed": elapsed}}) + "\\n")
    return result
'''

    try:
        for path in (TRUE_CALLS, APPROX_CALLS, LOG):
            if os.path.exists(path):
                os.remove(path)
        shutil.rmtree(os.path.join(MODEL_DIR, "__pycache__"), ignore_errors=True)
        with open(TRUE_MODEL, "w") as f:
            f.write(textwrap.dedent(true_wrapper))
        with open(APPROX_MODEL, "w") as f:
            f.write(textwrap.dedent(approx_wrapper))

        completed = subprocess.run(
            ["python3", "-B", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert completed.returncode == 0, (
            "benchmark.py failed when executed.\nSTDOUT:\n"
            + completed.stdout
            + "\nSTDERR:\n"
            + completed.stderr
        )

        assert os.path.isfile(LOG), "/home/user/experiment_log.json is missing. Did you run the script?"
        with open(LOG) as f:
            results = json.load(f)

        with open(TRUE_CALLS) as f:
            true_calls = [json.loads(line) for line in f if line.strip()]
        with open(APPROX_CALLS) as f:
            approx_calls = [json.loads(line) for line in f if line.strip()]

        # Each model must actually be executed ten times for benchmarking.
        assert len(true_calls) >= 10, f"compute_true was called only {len(true_calls)} times; at least 10 executions are required."
        assert len(approx_calls) >= 10, f"compute_approx was called only {len(approx_calls)} times; at least 10 executions are required."

        x = np.linspace(0.0, 100.0, 1000000, dtype=np.float64)
        expected_true = np.exp(-x / 10.0) * np.sin(x) * np.cos(2 * x)
        x32 = x.astype(np.float32)
        expected_approx = (
            np.exp(-x32 / 10.0) * np.sin(x32) * np.cos(2 * x32)
        ).astype(np.float64) + delta * (x / 100.0)
        expected_mse = float(np.mean((expected_true - expected_approx) ** 2))
        expected_max = float(np.max(np.abs(expected_true - expected_approx)))

        assert math.isclose(results["mse"], expected_mse, rel_tol=1e-8, abs_tol=1e-18), (
            f"Reported MSE {results['mse']} does not match recomputed MSE {expected_mse}."
        )
        assert math.isclose(results["max_abs_error"], expected_max, rel_tol=1e-8, abs_tol=1e-12), (
            f"Reported max absolute error {results['max_abs_error']} does not match recomputed value {expected_max}."
        )

        # Compare reported averages with the durations observed inside the last ten calls.
        true_observed_ms = sum(c["elapsed"] for c in true_calls[-10:]) * 1000.0 / 10.0
        approx_observed_ms = sum(c["elapsed"] for c in approx_calls[-10:]) * 1000.0 / 10.0
        for name, reported, observed in (
            ("true_time_ms", float(results["true_time_ms"]), true_observed_ms),
            ("approx_time_ms", float(results["approx_time_ms"]), approx_observed_ms),
        ):
            assert reported >= observed * 0.85, f"{name} is too small to represent the measured model executions."
            assert reported <= observed * 1.75 + 20.0, f"{name} is inconsistent with the measured model executions."

        expected_speedup = float(results["true_time_ms"]) / float(results["approx_time_ms"])
        assert math.isclose(float(results["speedup"]), expected_speedup, rel_tol=0.05, abs_tol=1e-9), (
            "speedup must equal true_time_ms / approx_time_ms."
        )
        yield
    finally:
        with open(TRUE_MODEL, "wb") as f:
            f.write(original_true)
        with open(APPROX_MODEL, "wb") as f:
            f.write(original_approx)
        shutil.rmtree(os.path.join(MODEL_DIR, "__pycache__"), ignore_errors=True)


def test_benchmark_script_exists():
    assert os.path.isfile(SCRIPT), "/home/user/benchmark.py script is missing."


def test_experiment_log_exists():
    assert os.path.isfile(LOG), "/home/user/experiment_log.json is missing. Did you run the script?"


def test_experiment_log_contents():
    with open(LOG, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/experiment_log.json is not a valid JSON file.")

    expected_keys = {"valid_shape_dtype", "mse", "max_abs_error", "true_time_ms", "approx_time_ms", "speedup"}
    assert set(results.keys()) == expected_keys, f"JSON keys do not match the expected keys. Found: {list(results.keys())}"

    assert results["valid_shape_dtype"] is True, "Validation of shape and dtype should be True."

    mse = results["mse"]
    assert isinstance(mse, float), "MSE must be a float."
    assert math.isfinite(mse), "MSE must be finite."
    assert mse >= 0, "MSE must be >= 0."
    assert mse < 1e-10, f"MSE is abnormally high: {mse}. Check your MSE calculation."

    max_abs_error = results["max_abs_error"]
    assert isinstance(max_abs_error, float), "Max absolute error must be a float."
    assert math.isfinite(max_abs_error), "Max absolute error must be finite."
    assert max_abs_error >= 0, "Max absolute error must be >= 0."
    assert max_abs_error < 1e-5, f"Max absolute error is abnormally high: {max_abs_error}. Check your calculation."

    assert isinstance(results["true_time_ms"], (int, float)), "true_time_ms must be a number."
    assert math.isfinite(results["true_time_ms"]), "true_time_ms must be finite."
    assert results["true_time_ms"] > 0, "true_time_ms must be > 0."

    assert isinstance(results["approx_time_ms"], (int, float)), "approx_time_ms must be a number."
    assert math.isfinite(results["approx_time_ms"]), "approx_time_ms must be finite."
    assert results["approx_time_ms"] > 0, "approx_time_ms must be > 0."

    assert isinstance(results["speedup"], (int, float)), "speedup must be a number."
    assert math.isfinite(results["speedup"]), "speedup must be finite."
    assert results["speedup"] > 0, "speedup must be > 0."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
