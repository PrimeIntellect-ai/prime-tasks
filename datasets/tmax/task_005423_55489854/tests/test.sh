#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import importlib
import importlib.machinery
import json
import math
import os
import subprocess
import sys

import pytest

BASE_DIR = "/home/user/metrics_service"
REPORT_PATH = os.path.join(BASE_DIR, "report.json")
AGGREGATOR_PATH = os.path.join(BASE_DIR, "aggregator.py")
DATA_PATH = os.path.join(BASE_DIR, "data.csv")


def expected_stats(path):
    values = []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            values.append(float(row[0]))
    assert values, "data.csv is empty"
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
    return mean, math.sqrt(variance)


def assert_correct_stats(data, expected_mean, expected_stddev):
    assert set(("mean", "stddev")).issubset(data)
    mean = data["mean"]
    stddev = data["stddev"]
    assert isinstance(mean, (int, float)), "mean must be numeric"
    assert isinstance(stddev, (int, float)), "stddev must be numeric"
    assert math.isfinite(mean), "mean must be finite"
    assert math.isfinite(stddev), "stddev must be finite"
    assert stddev >= 0, "stddev must be non-negative"
    assert math.isclose(mean, expected_mean, rel_tol=1e-12, abs_tol=1e-9), \
        f"incorrect mean: got {mean}, expected {expected_mean}"
    # Clamping a tiny negative variance to zero is explicitly allowed by the task.
    tolerance = max(1e-9, expected_stddev * 0.05, 2e-4)
    assert abs(stddev - expected_stddev) <= tolerance, \
        f"incorrect stddev: got {stddev}, expected {expected_stddev}"


def test_extension_was_built_and_is_exercised():
    sys.path.insert(0, BASE_DIR)
    try:
        sys.modules.pop("fast_stats", None)
        fast_stats = importlib.import_module("fast_stats")
    finally:
        sys.path.pop(0)

    module_path = os.path.realpath(fast_stats.__file__)
    assert os.path.isfile(module_path), "fast_stats extension artifact is missing"
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_stats is not a compiled Python extension: {module_path}"

    mean, stddev = fast_stats.compute_stats([1.0, 2.0, 3.0, 4.0])
    assert math.isclose(mean, 2.5, rel_tol=0, abs_tol=1e-12)
    assert math.isclose(stddev, math.sqrt(1.25), rel_tol=1e-12, abs_tol=1e-12)

    unstable = [1_000_000_000.0 + x for x in (-0.001, -0.0005, 0.0, 0.0005, 0.001)]
    mean, stddev = fast_stats.compute_stats(unstable)
    assert math.isfinite(mean)
    assert math.isfinite(stddev), "large-baseline input still produces NaN or infinity"
    assert stddev >= 0


def test_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON.")

    assert "mean" in data, "Key 'mean' missing from report.json."
    assert "stddev" in data, "Key 'stddev' missing from report.json."


def test_report_values():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    stddev = data.get("stddev")
    assert stddev is not None, "stddev is null or missing."
    assert isinstance(stddev, (int, float)), "stddev must be a numeric value."
    assert not math.isnan(stddev), "stddev is NaN, which means numerical instability was not fixed."
    assert stddev >= 0, "stddev is less than 0, which is mathematically invalid for standard deviation."

    expected_mean, expected_stddev = expected_stats(DATA_PATH)
    assert_correct_stats(data, expected_mean, expected_stddev)


def test_aggregator_assertion():
    assert os.path.isfile(AGGREGATOR_PATH), f"Aggregator script not found at {AGGREGATOR_PATH}"

    with open(AGGREGATOR_PATH, 'r') as f:
        content = f.read()

    assert "assert " in content, "No 'assert' statement found in aggregator.py."
    assert "isnan" in content, "No 'isnan' check found in aggregator.py. You should use math.isnan to check for NaN."

    sys.path.insert(0, BASE_DIR)
    try:
        sys.modules.pop("aggregator", None)
        aggregator = importlib.import_module("aggregator")
    finally:
        sys.path.pop(0)

    input_path = "/tmp/assertion_input.csv"
    with open(input_path, "w") as f:
        f.write("1.0\n")

    original_compute_stats = aggregator.fast_stats.compute_stats
    original_argv = sys.argv[:]
    try:
        for bad_stddev in (float("nan"), -1.0):
            output_path = f"/tmp/assertion_output_{str(bad_stddev).replace('-', 'neg')}.json"
            if os.path.exists(output_path):
                os.unlink(output_path)
            aggregator.fast_stats.compute_stats = lambda values, bad=bad_stddev: (1.0, bad)
            sys.argv = [AGGREGATOR_PATH, input_path, output_path]
            with pytest.raises(AssertionError):
                aggregator.main()
            assert not os.path.exists(output_path), \
                "validation assertion must run before the result is written"
    finally:
        aggregator.fast_stats.compute_stats = original_compute_stats
        sys.argv = original_argv


def test_fresh_service_execution(tmp_path):
    output_path = tmp_path / "fresh_report.json"
    completed = subprocess.run(
        [sys.executable, AGGREGATOR_PATH, DATA_PATH, str(output_path)],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert output_path.is_file(), "aggregator did not create its requested output"
    with output_path.open() as f:
        data = json.load(f)
    expected_mean, expected_stddev = expected_stats(DATA_PATH)
    assert_correct_stats(data, expected_mean, expected_stddev)
TEST_EOF

passed=1
cd /home/user/metrics_service || passed=0
if [ "$passed" -eq 1 ]; then
    rm -rf build
    rm -f fast_stats*.so
    if ! python3 setup.py build_ext --inplace >/tmp/build.log 2>&1; then
        cat /tmp/build.log
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
