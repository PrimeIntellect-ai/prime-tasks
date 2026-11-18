#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import struct
import subprocess

import pytest

ENGINE_DIR = "/home/user/engine"
SOURCE_PATH = os.path.join(ENGINE_DIR, "src/main.rs")
EXECUTABLE = os.path.join(ENGINE_DIR, "target/release/engine")
CRASH_PATH = "/home/user/crash.bin"
RESULT_PATH = "/home/user/result.txt"
MARKER = b"FAIL_X_VAL="
TOLERANCE = 1e-7


def stable_expected(x):
    if x == 0.0:
        return 0.5
    half = x / 2.0
    return 0.5 * (math.sin(half) / half) ** 2


def parse_single_float_output(output):
    lines = output.strip().splitlines()
    assert len(lines) == 1 and lines[0].strip(), \
        f"Engine must print only one floating-point result, got: {output!r}"
    try:
        value = float(lines[0].strip())
    except ValueError:
        pytest.fail(f"Engine output is not a valid float: {output!r}")
    assert math.isfinite(value), f"Engine returned a non-finite value: {value}"
    return value


def run_engine(executable, x):
    completed = subprocess.run(
        [executable, repr(x)],
        cwd=ENGINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, \
        f"Engine failed for x={x}: {completed.stderr}"
    return parse_single_float_output(completed.stdout)


@pytest.fixture(scope="session")
def built_engine():
    assert os.path.isfile(SOURCE_PATH), f"Rust source missing: {SOURCE_PATH}"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), \
        f"Rust source is not a regular file: {SOURCE_PATH}"

    clean = subprocess.run(
        ["cargo", "clean"], cwd=ENGINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert clean.returncode == 0, f"cargo clean failed: {clean.stderr}"

    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=ENGINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, f"Engine did not compile: {build.stderr}"
    assert os.path.isfile(EXECUTABLE), f"Compiled engine missing: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Compiled engine is not executable: {EXECUTABLE}"
    return EXECUTABLE


def test_result_accuracy():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Expected result file missing: {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content, f"Result file {result_path} is empty"

    try:
        result_val = float(content)
    except ValueError:
        pytest.fail(f"Result file {result_path} does not contain a valid float: {content}")

    expected = 0.5
    error = abs(result_val - expected)
    tolerance = 1e-7

    assert error <= tolerance, f"Numerical error {error} exceeds tolerance {tolerance}. Result was {result_val}, expected ~{expected}."


def test_crash_input_and_saved_result(built_engine):
    assert os.path.isfile(CRASH_PATH), f"Crash dump missing: {CRASH_PATH}"
    with open(CRASH_PATH, "rb") as f:
        data = f.read()

    marker_pos = data.find(MARKER)
    assert marker_pos >= 0, "FAIL_X_VAL marker missing from crash dump"
    value_pos = marker_pos + len(MARKER)
    assert len(data) >= value_pos + 8, "Crash dump does not contain an f64 after the marker"
    crash_x = struct.unpack("<d", data[value_pos:value_pos + 8])[0]

    actual = run_engine(built_engine, crash_x)
    expected = stable_expected(crash_x)
    assert abs(actual - expected) <= TOLERANCE, \
        f"Engine is inaccurate for extracted crash x={crash_x}: got {actual}, expected {expected}"

    with open(RESULT_PATH, "r") as f:
        saved = float(f.read().strip())
    assert math.isfinite(saved), f"Saved result is non-finite: {saved}"
    assert abs(saved - actual) <= 1e-12, \
        f"Saved result {saved} does not match the rebuilt engine output {actual} for the crash input"


def test_formula_on_unpredictable_inputs(built_engine):
    rng = secrets.SystemRandom()
    cases = []

    # Very small values expose catastrophic cancellation in the original code.
    for _ in range(8):
        magnitude = 10.0 ** rng.uniform(-14.0, -5.0)
        cases.append(magnitude if rng.randrange(2) else -magnitude)

    # Larger values ensure the implementation computes the formula rather than
    # simply returning its small-x limit of 0.5.
    for _ in range(8):
        magnitude = rng.uniform(0.02, 3.0)
        cases.append(magnitude if rng.randrange(2) else -magnitude)

    for x in cases:
        actual = run_engine(built_engine, x)
        expected = stable_expected(x)
        error = abs(actual - expected)
        assert error <= TOLERANCE, \
            f"Numerical error {error} exceeds {TOLERANCE} for x={x}: got {actual}, expected {expected}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
