#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
from fractions import Fraction

SCRIPT = "/home/user/fixed_service.sh"
STREAM = "/home/user/stream.txt"
FINAL = "/home/user/final_variance.txt"


def test_fixed_service_exists_and_executable():
    path = SCRIPT
    assert os.path.exists(path), f"Missing fixed service script: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {path}"


def test_final_variance_correct():
    path = FINAL
    assert os.path.exists(path), f"Missing final variance file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {path} is not a valid number: {content}"

    assert abs(val - 8.25) < 1e-5, f"Expected final variance to be 8.25, got {val}"


def test_fixed_service_logic():
    path = SCRIPT
    with open(path, "r") as f:
        content = f.read()

    # Check that it doesn't just infinitely append to a bash array like the original.
    # If it uses bash arrays, it should have a way to remove old elements or use modulo.
    if "history+=(" in content or "history+=(" in content.replace(" ", ""):
        assert "unset" in content or "shift" in content or "${history[@]:" in content, \
            "Script still appears to append to an array without removing old elements (memory leak)."


def expected_variances(values):
    result = []
    for end in range(10, len(values) + 1):
        window = values[end - 10:end]
        mean = sum(Fraction(v) for v in window) / 10
        variance = sum((Fraction(v) - mean) ** 2 for v in window) / 10
        result.append(float(variance))
    return result


def run_and_check(values):
    with open(STREAM, "w") as f:
        for value in values:
            f.write(f"{value}\n")

    proc = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=False,
    )
    assert proc.returncode == 0, \
        f"Fixed service exited with status {proc.returncode}: {proc.stderr}"

    lines = proc.stdout.strip().splitlines() if proc.stdout.strip() else []
    expected = expected_variances(values)
    assert len(lines) == len(expected), \
        f"Expected {len(expected)} variance lines, got {len(lines)}"

    for index, (line, wanted) in enumerate(zip(lines, expected), start=1):
        try:
            actual = float(line.strip())
        except ValueError:
            assert False, f"Output line {index} is not numeric: {line!r}"
        assert math.isfinite(actual), f"Output line {index} is not finite: {line!r}"
        tolerance = max(1e-5, abs(wanted) * 2e-5)
        assert abs(actual - wanted) <= tolerance, \
            f"Wrong variance on output line {index}: expected {wanted}, got {actual}"

    return lines


def test_fixed_service_executes_and_computes_stable_rolling_variance():
    with open(STREAM, "rb") as f:
        original_stream = f.read()

    rng = secrets.SystemRandom()
    base = rng.randrange(100_000_000, 900_000_000)
    random_values = [base + rng.randrange(-75, 76) for _ in range(37)]
    fixed_values = [
        700_000_003, 700_000_011, 699_999_997, 700_000_025, 699_999_981,
        700_000_006, 699_999_992, 700_000_018, 699_999_989, 700_000_031,
        700_000_002, 699_999_976, 700_000_014, 699_999_995, 700_000_022,
    ]

    try:
        run_and_check(fixed_values)
        run_and_check(random_values)
    finally:
        with open(STREAM, "wb") as f:
            f.write(original_stream)

    # Also execute the submitted artifact on the supplied stream and ensure the
    # saved final result is actually its last rolling-variance output.
    proc = subprocess.run(
        [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60, check=False
    )
    assert proc.returncode == 0, \
        f"Fixed service failed on the supplied stream: {proc.stderr}"
    lines = proc.stdout.strip().splitlines() if proc.stdout.strip() else []
    assert len(lines) == 991, f"Expected 991 output windows on stream.txt, got {len(lines)}"
    try:
        last_output = float(lines[-1])
        with open(FINAL, "r") as f:
            saved = float(f.read().strip())
    except ValueError as exc:
        assert False, f"Non-numeric final output or saved variance: {exc}"
    assert abs(last_output - 8.25) < 1e-5, \
        f"Expected final script output 8.25, got {last_output}"
    assert abs(saved - last_output) < 1e-5, \
        f"Saved final variance {saved} does not match script output {last_output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
