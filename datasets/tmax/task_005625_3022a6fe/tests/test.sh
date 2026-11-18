#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import re
import subprocess
import pytest

REPORT_PATH = "/home/user/regression_report.json"
SOURCE_PATH = "/home/user/sum_sim.c"
BINARY_PATH = "/tmp/sum_sim_verifier"


def solve_root():
    lo, hi = 0.0, 1.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        value = mid * mid * mid - 4.0 * mid + 1.0
        if value > 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def python_ground_truth(root):
    return math.fsum(root / (n * n + root * root) for n in range(1, 1000001))


def compile_and_run(root):
    assert os.path.isfile(SOURCE_PATH), f"The C source {SOURCE_PATH} does not exist."
    subprocess.run(
        ["/usr/bin/gcc", "-std=c11", SOURCE_PATH, "-o", BINARY_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    result = subprocess.run(
        [BINARY_PATH, format(root, ".17g")],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    forward_match = re.search(r"^Forward:\s*([-+0-9.eE]+)\s*$", result.stdout, re.MULTILINE)
    backward_match = re.search(r"^Backward:\s*([-+0-9.eE]+)\s*$", result.stdout, re.MULTILINE)
    assert forward_match, f"Could not parse Forward result from C output: {result.stdout!r}"
    assert backward_match, f"Could not parse Backward result from C output: {result.stdout!r}"
    return float(forward_match.group(1)), float(backward_match.group(1))


def test_regression_report_exists():
    """Check if the regression report JSON file exists."""
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."


def test_regression_report_content():
    """Validate the report against independently computed and executed results."""
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} is not valid JSON.")

    expected_keys = {"root", "c_forward", "c_backward", "python_true", "more_accurate_method"}
    assert set(data.keys()) == expected_keys, f"The JSON file must contain exactly the keys: {expected_keys}"

    root = data["root"]
    assert isinstance(root, float), "'root' must be a float."
    assert abs(root - 0.25410168836) < 1e-5, f"'root' value {root} is incorrect."

    assert isinstance(data["c_forward"], float), "'c_forward' must be a float."
    assert isinstance(data["c_backward"], float), "'c_backward' must be a float."

    python_true = data["python_true"]
    assert isinstance(python_true, float), "'python_true' must be a float."
    assert abs(python_true - 0.417983675) < 1e-5, f"'python_true' value {python_true} is incorrect."

    method = data["more_accurate_method"]
    assert method == "backward", f"'more_accurate_method' should be 'backward', but got '{method}'."

    expected_root = solve_root()
    expected_true = python_ground_truth(expected_root)
    actual_forward, actual_backward = compile_and_run(expected_root)

    assert math.isfinite(data["c_forward"]), "'c_forward' must be finite."
    assert math.isfinite(data["c_backward"]), "'c_backward' must be finite."
    assert math.isfinite(python_true), "'python_true' must be finite."
    assert abs(data["c_forward"] - actual_forward) <= 5e-9, (
        f"'c_forward' {data['c_forward']} does not match the compiled C program output {actual_forward}."
    )
    assert abs(data["c_backward"] - actual_backward) <= 5e-9, (
        f"'c_backward' {data['c_backward']} does not match the compiled C program output {actual_backward}."
    )
    assert abs(python_true - expected_true) <= 1e-9, (
        f"'python_true' {python_true} does not match the independently computed float64 sum {expected_true}."
    )

    forward_error = abs(actual_forward - expected_true)
    backward_error = abs(actual_backward - expected_true)
    expected_method = "forward" if forward_error < backward_error else "backward"
    assert method == expected_method, (
        f"'more_accurate_method' should be '{expected_method}' based on errors "
        f"forward={forward_error}, backward={backward_error}, but got '{method}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
