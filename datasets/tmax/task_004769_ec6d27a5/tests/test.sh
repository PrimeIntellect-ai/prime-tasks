#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest

BINARY_PATH = "/home/user/bin/calc_energy"


def run_calc_energy(input_text):
    proc = subprocess.run(
        [BINARY_PATH],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"calc_energy exited with status {proc.returncode}: {proc.stderr}"
    )
    assert proc.stderr == "", f"calc_energy produced unexpected stderr: {proc.stderr!r}"
    return proc.stdout


def test_calc_energy_binary_exists():
    binary_path = "/home/user/bin/calc_energy"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc_energy is not a compiled ELF executable"


def test_calc_energy_binary_behavior():
    cases = [
        [],
        [1.5, 2.0, 3.0],
        [-2.0, 0.5, 4.25],
    ]

    # Add unpredictable, exactly representable values so answers are derived by
    # the verifier rather than trusted from a submitted artifact.
    for _ in range(10):
        count = 1 + secrets.randbelow(12)
        cases.append([(secrets.randbelow(257) - 128) / 8.0 for _ in range(count)])

    for values in cases:
        expected = f"{sum(value * value for value in values):.4f}\n"
        input_text = " \t\n".join(str(value) for value in values)
        actual = run_calc_energy(input_text)
        assert actual == expected, (
            f"calc_energy returned {actual!r} for {values!r}; expected {expected!r}"
        )

    # Exercise the compiled program on every signal used by the regression.
    with open("/home/user/data/signals.txt", "r") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            values = [float(value) for value in parts]
            expected = f"{sum(value * value for value in values):.4f}\n"
            assert run_calc_energy(line) == expected


def test_supplied_regression_script_passes():
    script_path = "/home/user/src/test_energy.sh"
    assert os.path.isfile(script_path), f"Regression test script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Regression test script is not executable: {script_path}"

    proc = subprocess.run(
        [script_path],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"test_energy.sh failed with status {proc.returncode}: "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert proc.stdout.strip() == "PASS", (
        f"test_energy.sh did not output PASS: {proc.stdout!r}"
    )


def test_regression_results():
    results_path = "/home/user/regression_results.txt"
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"

    signals_path = "/home/user/data/signals.txt"
    targets_path = "/home/user/data/targets.txt"

    assert os.path.isfile(signals_path), "Signals file missing"
    assert os.path.isfile(targets_path), "Targets file missing"

    # Compute expected x (energies)
    x = []
    with open(signals_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            energy = sum(float(val)**2 for val in parts)
            x.append(energy)

    # Compute expected y (targets)
    y = []
    with open(targets_path, 'r') as f:
        for line in f:
            val = line.strip()
            if not val:
                continue
            y.append(float(val))

    assert len(x) == len(y), "Mismatch in number of signals and targets"
    N = len(x)
    assert N > 0, "No data found"

    # Calculate linear regression
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i] * y[i] for i in range(N))
    sum_x2 = sum(x[i]**2 for i in range(N))

    denominator = (N * sum_x2 - sum_x**2)
    assert denominator != 0, "Denominator for slope is zero"

    m = (N * sum_xy - sum_x * sum_y) / denominator
    b = (sum_y - m * sum_x) / N

    expected_output = f"Slope: {m:.4f}, Intercept: {b:.4f}"

    with open(results_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_output, (
        f"Incorrect regression results.\n"
        f"Expected: '{expected_output}'\n"
        f"Actual:   '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
