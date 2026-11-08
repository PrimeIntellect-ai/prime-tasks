#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import numbers
import os
import secrets
import subprocess
import sys
from decimal import Decimal, localcontext

import pytest


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def reference_population_stddev(values):
    if not values:
        return 0.0
    with localcontext() as ctx:
        ctx.prec = 80
        converted = [Decimal.from_float(float(value)) for value in values]
        mean = sum(converted) / Decimal(len(converted))
        variance = sum((value - mean) ** 2 for value in converted) / Decimal(len(converted))
        return float(variance.sqrt())


def test_incident_report_content():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"Incident report missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in incident report, found {len(lines)}"
    assert lines[0] == "TIMESTAMP: 2024-10-27T03:14:15Z", f"Incorrect TIMESTAMP line: {lines[0]}"
    assert lines[1] == "FIXED_VOLATILITY: 0.00", f"Incorrect FIXED_VOLATILITY line: {lines[1]}"
    assert lines[2] == "BUILD_STATUS: SUCCESS", f"Incorrect BUILD_STATUS line: {lines[2]}"


def test_predictor_volatility_fixed():
    predictor_path = "/home/user/service/predictor.py"
    assert os.path.isfile(predictor_path), f"{predictor_path} is missing."

    try:
        predictor = load_module("predictor", predictor_path)
    except Exception as e:
        pytest.fail(f"Failed to import predictor.py: {e}")

    assert hasattr(predictor, "compute_volatility"), "compute_volatility function is missing in predictor.py"

    # Preserve the original large-constant regression check.
    try:
        result = predictor.compute_volatility([1e10, 1e10, 1e10])
    except Exception as e:
        pytest.fail(f"compute_volatility threw an exception on large floats: {e}")
    assert abs(result - 0.0) < 1e-5, f"Expected volatility to be 0.0, got {result}"

    # Exercise nonzero variance, including unpredictable large baselines where the
    # naive E[X^2] - E[X]^2 formula loses precision. Expected values are derived
    # independently using high-precision decimal arithmetic.
    baseline = float(10**12 + secrets.randbelow(10**6))
    scale = 1 + secrets.randbelow(20)
    cases = [
        [],
        [42.25],
        [10.0, 12.0, 10.0],
        [-7.5, -2.0, 4.25, 11.0],
        [1e10 - 0.125, 1e10, 1e10 + 0.125, 1e10 + 0.375],
        [baseline - 3.5 * scale, baseline - 0.5 * scale,
         baseline + 1.5 * scale, baseline + 4.5 * scale],
    ]

    for data in cases:
        expected = reference_population_stddev(data)
        try:
            actual = predictor.compute_volatility(list(data))
        except Exception as e:
            pytest.fail(f"compute_volatility({data!r}) raised {e!r}")
        assert isinstance(actual, numbers.Real) and not isinstance(actual, bool), \
            f"compute_volatility({data!r}) returned a non-numeric result: {actual!r}"
        actual = float(actual)
        assert math.isfinite(actual), f"compute_volatility({data!r}) returned {actual!r}"
        tolerance = max(1e-10, abs(expected) * 1e-9)
        assert abs(actual - expected) <= tolerance, \
            f"compute_volatility({data!r}) returned {actual}, expected {expected}"


def test_build_script_fixed():
    build_path = "/home/user/service/build.py"
    assert os.path.isfile(build_path), f"{build_path} is missing."

    with open(build_path, "r") as f:
        content = f.read()

    assert "<<<<<<< HEAD" not in content, "Git merge conflict markers still present in build.py"
    assert "=======" not in content, "Git merge conflict markers still present in build.py"
    assert ">>>>>>>" not in content, "Git merge conflict markers still present in build.py"

    # Preserve the original end-to-end execution assertion.
    result = subprocess.run(
        [sys.executable, build_path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, \
        f"build.py exited with code {result.returncode}. Output: {result.stdout}\n{result.stderr}"

    # A successful no-op is not a repaired build: run_tests must still execute the
    # volatility test from one of the two conflicted branches.
    predictor = load_module("predictor", "/home/user/service/predictor.py")
    build = load_module("repaired_build", build_path)
    assert callable(getattr(build, "run_tests", None)), "build.py is missing run_tests()"

    calls = []
    real_compute = predictor.compute_volatility

    def recording_compute(data):
        calls.append(tuple(data))
        return real_compute(data)

    predictor.compute_volatility = recording_compute
    if hasattr(build, "compute_volatility"):
        build.compute_volatility = recording_compute
    try:
        build.run_tests()
    except Exception as e:
        pytest.fail(f"build.py run_tests() failed: {e}")

    expected_branch_inputs = {(10.0, 12.0, 10.0), (10.0, 10.0, 10.0)}
    assert any(call in expected_branch_inputs for call in calls), \
        "build.py run_tests() did not execute the volatility test from either merge branch"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
