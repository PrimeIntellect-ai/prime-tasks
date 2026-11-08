#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import sys
import math
import inspect
import random
import subprocess
import importlib.util


def load_math_compute():
    module_path = "/home/user/math_compute.py"
    assert os.path.isfile(module_path), f"{module_path} does not exist."

    spec = importlib.util.spec_from_file_location("math_compute_under_test", module_path)
    assert spec is not None and spec.loader is not None, f"Could not load {module_path}."
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as e:
        assert False, f"Failed to import {module_path}: {e}"
    return module


def test_anomaly_report_exists_and_valid():
    report_path = "/home/user/anomaly_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} is not valid JSON."

    expected_keys = {"slow_request_id", "anomaly_feature"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, got {set(data.keys())}"
    assert data["slow_request_id"] == "REQ-103", f"Expected slow_request_id to be 'REQ-103', got {data['slow_request_id']}"
    assert data["anomaly_feature"] in {"StdDev", "Variance"}, f"Expected anomaly_feature to identify a zero-valued feature, got {data['anomaly_feature']}"
    assert data["anomaly_feature"] == "StdDev", f"The source-code trigger is std == 0.0, so anomaly_feature must be 'StdDev', got {data['anomaly_feature']}"


def test_math_compute_behavior():
    math_compute = load_math_compute()
    assert hasattr(math_compute, "normalize_and_compute"), "Function 'normalize_and_compute' is missing from math_compute.py"
    assert callable(math_compute.normalize_and_compute), "normalize_and_compute must be callable"

    signature = inspect.signature(math_compute.normalize_and_compute)
    assert list(signature.parameters) == ["data"], f"normalize_and_compute signature must remain normalize_and_compute(data), got {signature}"

    # Preserve the original fixed behavioral and timing assertion.
    test_data = [5.0, 5.0, 5.0, 5.0, 5.0]
    start_time = time.monotonic()
    try:
        result = math_compute.normalize_and_compute(test_data)
    except Exception as e:
        assert False, f"normalize_and_compute raised an exception: {e}"
    duration = time.monotonic() - start_time
    assert duration < 1.0, f"normalize_and_compute took {duration:.2f}s, which is too long (expected < 1.0s). Did you fix the slow fallback?"
    assert result == [0.0, 0.0, 0.0, 0.0, 0.0], f"Expected output [0.0, 0.0, 0.0, 0.0, 0.0], got {result}"

    # Every zero-standard-deviation input must bypass slow_fallback_compute.
    assert hasattr(math_compute, "slow_fallback_compute"), "slow_fallback_compute is missing"
    original_fallback = math_compute.slow_fallback_compute

    def forbidden_fallback(data):
        raise AssertionError("slow_fallback_compute was called for zero standard deviation")

    math_compute.slow_fallback_compute = forbidden_fallback
    try:
        constant_cases = [
            [],
            [9.0],
            [0.0, 0.0],
            [-4.0] * 7,
            [32.0] * 19,
        ]
        for values in constant_cases:
            started = time.monotonic()
            output = math_compute.normalize_and_compute(values)
            elapsed = time.monotonic() - started
            assert elapsed < 1.0, f"Zero-StdDev input of length {len(values)} took {elapsed:.2f}s"
            assert output == [0.0] * len(values), f"Expected {len(values)} zeros for {values}, got {output}"
    finally:
        math_compute.slow_fallback_compute = original_fallback

    # Derive expected normalization results independently for varied nonconstant inputs.
    cases = [
        [1.0, 2.0, 3.0],
        [-8.0, -1.0, 2.0, 11.0],
        [0.5, 2.5],
        [10.0, 10.0, 12.0, 14.0, 19.0],
    ]
    rng = random.SystemRandom()
    for _ in range(8):
        length = rng.randrange(2, 18)
        values = [float(rng.randrange(-100, 101)) for _ in range(length)]
        if len(set(values)) == 1:
            values[-1] += 1.0
        cases.append(values)

    for values in cases:
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / len(values)
        std = math.sqrt(variance)
        expected = [(x - mean) / std for x in values]

        output = math_compute.normalize_and_compute(values)
        assert isinstance(output, list), f"Expected a list for nonconstant input, got {type(output).__name__}"
        assert len(output) == len(expected), f"Expected output length {len(expected)}, got {len(output)}"
        for index, (actual, wanted) in enumerate(zip(output, expected)):
            assert math.isclose(actual, wanted, rel_tol=1e-9, abs_tol=1e-9), \
                f"Incorrect normalized value at index {index} for {values}: expected {wanted}, got {actual}"


def test_success_log_exists_after_running_verification_script():
    verify_path = "/home/user/verify.py"
    success_path = "/home/user/success.log"
    assert os.path.isfile(verify_path), f"Verification script {verify_path} does not exist."

    # Do not trust a pre-created success marker: require verify.py to create it now.
    if os.path.lexists(success_path):
        os.remove(success_path)
    try:
        completed = subprocess.run(
            [sys.executable, verify_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=2.5,
        )
    except subprocess.TimeoutExpired:
        assert False, "verify.py timed out; the slow fallback is still being used"

    assert completed.returncode == 0, f"verify.py failed with output:\n{completed.stdout}"
    assert os.path.isfile(success_path), f"Success log {success_path} does not exist after running verify.py."
    with open(success_path, "r") as f:
        content = f.read().strip()
    assert content == "VERIFICATION_PASSED", f"Expected 'VERIFICATION_PASSED' in {success_path}, got {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
