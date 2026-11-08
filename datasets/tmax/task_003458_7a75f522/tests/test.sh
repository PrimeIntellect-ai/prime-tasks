#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

APP_DIR = "/home/user/telemetry_app"
MAIN_PATH = os.path.join(APP_DIR, "src/main.rs")
BINARY_PATH = os.path.join(APP_DIR, "target/release/telemetry_app")
SENSORS_PATH = os.path.join(APP_DIR, "data/sensors.log")
DIAG_PATH = "/home/user/diagnostics.txt"
NUMBER_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


@pytest.fixture(scope="session", autouse=True)
def build_application():
    assert os.path.isfile(os.path.join(APP_DIR, "Cargo.toml")), "Cargo.toml is missing."
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"The Rust application did not build:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), f"Expected executable {BINARY_PATH} was not produced."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The built application is not an ELF executable."


def run_app(path):
    result = subprocess.run(
        [BINARY_PATH, path],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Application failed on {path} with exit code {result.returncode}:\n"
        f"{result.stderr.decode(errors='replace')}"
    )
    text = result.stdout.decode("utf-8")
    match = re.fullmatch(rf"Average: ({NUMBER_RE})\n?", text)
    assert match, f"Unexpected application output: {text!r}"
    value = float(match.group(1))
    assert math.isfinite(value), f"Application produced a non-finite average: {value}"
    return result.stdout, value


def test_diagnostics_file_correct():
    assert os.path.isfile(DIAG_PATH), f"The file {DIAG_PATH} does not exist. Did you save the output?"

    with open(DIAG_PATH, "r") as f:
        content = f.read().strip()

    # Preserve the original expected-result assertion.
    assert "Average: 3750000.25" in content, (
        f"Incorrect average in {DIAG_PATH}. Expected 'Average: 3750000.25', but got:\n{content}\n"
        "Check if you properly skipped malformed lines and used f64 for precision."
    )

    stdout, value = run_app(SENSORS_PATH)
    assert math.isclose(value, 3750000.25, rel_tol=0.0, abs_tol=1e-12)
    with open(DIAG_PATH, "rb") as f:
        diagnostics = f.read()
    assert diagnostics == stdout, (
        "diagnostics.txt must contain exactly the output produced by the fixed application "
        "when run against data/sensors.log."
    )


def test_main_rs_uses_f64():
    assert os.path.isfile(MAIN_PATH), f"The file {MAIN_PATH} does not exist."
    with open(MAIN_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertion; behavioral tests below ensure it is real.
    assert "f64" in content, (
        "The source code does not appear to use 'f64'. You must upgrade the math logic to use 64-bit precision."
    )


def test_randomized_parsing_and_f64_aggregation():
    rng = random.SystemRandom()

    # Odd integers at this magnitude and small binary fractions expose f32 rounding,
    # while remaining exactly representable and straightforward to aggregate in f64.
    large = rng.randrange(33_554_433, 536_870_911, 2)
    negative = -rng.randrange(10_001, 900_001)
    values = [float(large), 0.125, 0.25, 0.5, float(negative) + 0.75, 3.125]
    expected = sum(values) / len(values)

    lines = [
        f"1700000000,sensorA,{values[0]}",
        "1700000001,sensorA,ERR",
        f"1700000002,sensorA, {values[1]} ",
        "1700000003,sensorA,1.2.3",
        f"1700000004,sensorA,{values[2]}",
        "malformed-line-without-columns",
        f"1700000005,sensorA,{values[3]}",
        "1700000006,sensorA,BAD_DATA",
        f"1700000007,sensorA,{values[4]}",
        "1700000008,sensorA,",
        "1700000009,sensorA,12,extra-column",
        f"1700000010,sensorA,{values[5]}",
    ]

    with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
        f.write("\n".join(lines) + "\n")
        path = f.name

    try:
        _, actual = run_app(path)
    finally:
        os.unlink(path)

    assert math.isclose(actual, expected, rel_tol=1e-14, abs_tol=1e-12), (
        f"Incorrect average for mixed valid and malformed input: expected {expected!r}, got {actual!r}. "
        "The program must skip unparseable values and aggregate using f64."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
