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

SCRIPT_PATH = "/home/user/logistic_euler.sh"
STRAINS_PATH = "/home/user/strains.txt"
REFERENCE_PATH = "/home/user/reference.txt"
MAE_PATH = "/home/user/mae.txt"

EXPECTED_STRAINS = [
    ("Alpha", 100.0, 0.5),
    ("Beta", 50.0, 1.8),
    ("Gamma", 10.0, 2.5),
    ("Delta", 200.0, 0.1),
]
EXPECTED_REFERENCES = {
    "Alpha": 942.8441,
    "Beta": 1000.0000,
    "Gamma": 1000.0000,
    "Delta": 404.6097,
}
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def reference_euler(n0, r):
    n = float(n0)
    dt = 0.01
    # The requested inclusive boundary executes at t=0, 0.01, ..., 10.00.
    for _ in range(1001):
        n += r * n * (1.0 - n / 1000.0) * dt
    return n


def run_script(n0, r):
    try:
        result = subprocess.run(
            [SCRIPT_PATH, format(n0, ".15g"), format(r, ".15g")],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Could not execute {SCRIPT_PATH}: {exc}")

    assert result.returncode == 0, (
        f"Script failed for N0={n0}, r={r}: {result.stderr}"
    )
    output = result.stdout.strip()
    assert NUMBER_RE.fullmatch(output), (
        f"Script must print exactly one numeric result; got {output!r}"
    )
    value = float(output)
    assert math.isfinite(value), "Script returned a non-finite population."
    return value


def test_logistic_euler_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "0.01" in content, "The script does not seem to use the dt=0.01 step size as requested."
    assert "dt = 2" not in content, "The script still contains the bad step size dt = 2."
    first_line = content.splitlines()[0] if content.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, (
        "logistic_euler.sh must be an executable Bash script."
    )

    # Exercise fixed and verification-time-random inputs so source keywords or
    # hardcoded answers cannot substitute for the Euler integration.
    cases = [(100.0, 0.1), (250.0, 0.2), (850.0, 0.12)]
    rng = random.SystemRandom()
    cases.extend(
        (rng.uniform(20.0, 750.0), rng.uniform(0.08, 0.45))
        for _ in range(7)
    )

    for n0, r in cases:
        actual = run_script(n0, r)
        expected = reference_euler(n0, r)
        assert abs(actual - expected) <= 0.0007, (
            f"Incorrect Euler result for N0={n0}, r={r}: "
            f"got {actual}, expected {expected}. Check dt and inclusive loop boundaries."
        )


def test_mae_calculated():
    assert os.path.isfile(MAE_PATH), f"File {MAE_PATH} does not exist."

    with open(MAE_PATH, "r") as f:
        mae_str = f.read().strip()

    assert mae_str, "mae.txt is empty."
    assert NUMBER_RE.fullmatch(mae_str), (
        f"mae.txt must contain a single floating-point number. Found: {mae_str!r}"
    )

    try:
        mae_val = float(mae_str)
    except ValueError:
        pytest.fail(f"mae.txt does not contain a valid floating-point number. Found: '{mae_str}'")
    assert math.isfinite(mae_val), "mae.txt contains a non-finite value."

    # Ensure the supplied datasets used by the task have not been replaced.
    with open(STRAINS_PATH, "r") as f:
        strain_rows = [line.split() for line in f if line.strip()]
    parsed_strains = [(row[0], float(row[1]), float(row[2])) for row in strain_rows]
    assert parsed_strains == EXPECTED_STRAINS, "strains.txt was modified or is malformed."

    with open(REFERENCE_PATH, "r") as f:
        reference_rows = [line.split() for line in f if line.strip()]
    parsed_references = {row[0]: float(row[1]) for row in reference_rows}
    assert parsed_references == EXPECTED_REFERENCES, "reference.txt was modified or is malformed."

    # Re-run the submitted artifact for every strain and independently recompute MAE.
    errors = []
    for name, n0, r in parsed_strains:
        calculated = run_script(n0, r)
        independently_expected = reference_euler(n0, r)
        assert abs(calculated - independently_expected) <= 0.0007, (
            f"Incorrect calculated population for strain {name}."
        )
        errors.append(abs(calculated - parsed_references[name]))
    recomputed_mae = sum(errors) / len(errors)
    assert abs(mae_val - recomputed_mae) <= 0.0005, (
        f"MAE value {mae_val} does not match the MAE recomputed from script outputs "
        f"and reference.txt ({recomputed_mae})."
    )

    # Preserve the original expected-value assertion.
    expected_mae = 0.16165
    tolerance = 0.01
    assert abs(mae_val - expected_mae) <= tolerance, \
        f"MAE value {mae_val} is not within the expected range (expected ~{expected_mae})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
