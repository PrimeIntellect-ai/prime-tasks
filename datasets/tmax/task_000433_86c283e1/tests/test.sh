#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

import pytest

PROJECT = "/home/user/diagnostic"
MAIN_RS = PROJECT + "/src/main.rs"
BINARY = PROJECT + "/target/debug/diagnostic"


def test_result_file_exists():
    assert os.path.isfile("/home/user/result.txt"), "Error: /home/user/result.txt not found."


def test_result_value_correct():
    with open('/home/user/result.txt', 'r') as f:
        content = f.read()

    match = re.search(r"Result:\s*(-?\d+\.\d+)", content)
    assert match is not None, "Error: /home/user/result.txt does not contain 'Result: <float>'."

    val = float(match.group(1))
    expected_val = -0.7596879128598213

    assert abs(val - expected_val) < 1e-5, f"Error: Output {val} does not match expected {expected_val} within tolerance."


def test_rust_code_fixes():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} is missing."

    with open(MAIN_RS, "r") as f:
        content = f.read()

    # Preserve the original precision assertions.
    assert "f32" not in content, "Error: f32 is still present in main.rs. Must be upgraded to f64."
    assert "f64" in content, "Error: f64 is not used in main.rs."

    # Preserve the original threshold assertion.
    assert "1e-12" in content or "1E-12" in content or "0.000000000001" in content, "Error: The termination condition must use 1e-12."

    # Ignore comments when checking that the implementation itself remains recursive.
    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    fn_match = re.search(r"fn\s+recursive_diagnostic\b[^\{]*\{", code)
    assert fn_match is not None, "Error: recursive_diagnostic function is missing."

    start = fn_match.end() - 1
    depth = 0
    end = None
    for i in range(start, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    assert end is not None, "Error: recursive_diagnostic has an invalid body."
    body = code[start + 1:end]
    assert re.search(r"\brecursive_diagnostic\s*\(", body), \
        "Error: recursive_diagnostic must recursively evaluate the series."


def parse_result(stdout):
    match = re.fullmatch(
        r"\s*Result:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*",
        stdout,
    )
    assert match is not None, f"Error: unexpected program output: {stdout!r}"
    value = float(match.group(1))
    assert math.isfinite(value), f"Error: non-finite result: {value}"
    return value


def run_diagnostic(x):
    completed = subprocess.run(
        [BINARY, format(x, ".17g")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert completed.returncode == 0, (
        f"diagnostic failed for x={x}: {completed.stderr}"
    )
    return completed.stdout, parse_result(completed.stdout)


def test_project_builds_and_recursive_series_is_correct():
    completed = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, f"cargo build failed:\n{completed.stdout}\n{completed.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "Error: cargo build did not produce an executable diagnostic binary."

    # Fixed edge/large cases plus verifier-generated inputs prevent a fixed-output solution.
    inputs = [0.0, 0.5, -1.25, 3.0, 7.5, 15.0, -15.0]
    rng = random.SystemRandom()
    inputs.extend(rng.uniform(-15.0, 15.0) for _ in range(8))

    output_at_15 = None
    for x in inputs:
        stdout, actual = run_diagnostic(x)
        expected = math.cos(x)
        assert abs(actual - expected) <= 2e-8, (
            f"Error: diagnostic({x}) returned {actual}, expected {expected}."
        )
        if x == 15.0:
            output_at_15 = stdout

    assert output_at_15 is not None
    with open("/home/user/result.txt", "r") as f:
        saved = f.read()
    assert saved.strip() == output_at_15.strip(), \
        "Error: result.txt is not the exact output produced by the repaired program for 15.0."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
