#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import numpy as np
import pytest

SCRIPT = "/home/user/analyze.sh"
RESULTS = "/home/user/results.txt"
DESIGN = "/home/user/design_matrix.csv"
TARGET = "/home/user/target.csv"
FOUR_DECIMALS = re.compile(r"^[+-]?\d+\.\d{4}$")


def reference_results(X, y):
    p = np.linalg.pinv(X, rcond=1e-2) @ y

    finals = []
    fine_trajectory = None
    for dt in (1.0, 0.1, 0.01):
        steps = int(round(100.0 / dt))
        z = np.empty(steps + 1, dtype=float)
        z[0] = 1.0
        for i in range(steps):
            t = i * dt
            z[i + 1] = z[i] + dt * (-p[0] * z[i] + p[1] * np.cos(p[2] * t))
        finals.append(z[-1])
        if dt == 0.01:
            fine_trajectory = z

    frequencies = np.fft.fftfreq(fine_trajectory.size, d=0.01)
    magnitudes = np.abs(np.fft.fft(fine_trajectory))
    positive = frequencies > 0
    peak = frequencies[positive][np.argmax(magnitudes[positive])]
    return [*p, *finals, peak]


def read_and_validate_results(expected):
    assert os.path.isfile(RESULTS), f"Missing required output file: {RESULTS}"
    with open(RESULTS, "r") as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == 5, f"Expected exactly 5 lines in {RESULTS}, found {len(raw_lines)}"
    lines = [line.strip() for line in raw_lines]
    assert all(lines), "All five report lines must be nonempty"

    p_parts = lines[0].split(',')
    assert len(p_parts) == 3, f"Line 1 should have 3 comma-separated values, found {len(p_parts)}"
    tokens = [part.strip() for part in p_parts] + lines[1:]
    assert len(tokens) == 7
    assert all(FOUR_DECIMALS.fullmatch(token) for token in tokens), \
        "Every reported value must use exactly four decimal places"

    try:
        actual = np.array([float(token) for token in tokens])
    except ValueError:
        pytest.fail("Report does not contain valid floats")
    assert np.all(np.isfinite(actual)), "Report values must be finite"

    expected_rounded = np.array([float(f"{value:.4f}") for value in expected])
    assert np.allclose(actual, expected_rounded, rtol=0.0, atol=1e-12), \
        f"Incorrect results: got {actual.tolist()}, expected {expected_rounded.tolist()}"


def run_and_validate(X, y):
    np.savetxt(DESIGN, X, delimiter=",")
    np.savetxt(TARGET, y, delimiter=",")
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [SCRIPT], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert completed.returncode == 0, \
        f"analyze.sh failed with exit code {completed.returncode}: {completed.stderr}"
    read_and_validate_results(reference_results(X, y))


def test_analyze_script_executable():
    path = SCRIPT
    assert os.path.isfile(path), f"Missing required script: {path}"
    assert os.access(path, os.X_OK), f"Script {path} is not executable"


def test_analyze_script_performs_pipeline():
    # Independently reconstruct the setup data so changing the supplied inputs
    # cannot make fabricated output self-consistent with the verifier.
    rng = np.random.RandomState(42)
    x1 = rng.randn(100)
    x2 = rng.randn(100)
    x3 = x1 + x2 + rng.randn(100) * 1e-4
    original_X = np.column_stack((x1, x2, x3))
    original_y = original_X @ np.array([0.5, 1.2, 3.0])

    disk_X = np.loadtxt(DESIGN, delimiter=",")
    disk_y = np.loadtxt(TARGET, delimiter=",")
    assert disk_X.shape == original_X.shape and np.allclose(disk_X, original_X, rtol=0, atol=1e-14), \
        "The supplied design matrix was modified"
    assert disk_y.shape == original_y.shape and np.allclose(disk_y, original_y, rtol=0, atol=1e-14), \
        "The supplied target vector was modified"

    design_backup = open(DESIGN, "rb").read()
    target_backup = open(TARGET, "rb").read()

    run_and_validate(original_X, original_y)

    # Exercise the script on a second near-singular instance generated only at
    # verification time, preventing a fixed five-line answer from passing.
    alt_rng = np.random.default_rng(20260911)
    a = alt_rng.normal(size=100)
    b = alt_rng.normal(size=100)
    c = a + b + alt_rng.normal(scale=1e-4, size=100)
    alternate_X = np.column_stack((a, b, c))
    alternate_y = alternate_X @ np.array([0.35, 0.8, 1.4])

    try:
        run_and_validate(alternate_X, alternate_y)
    finally:
        with open(DESIGN, "wb") as f:
            f.write(design_backup)
        with open(TARGET, "wb") as f:
            f.write(target_backup)

    # Leave the required report corresponding to the original supplied data.
    run_and_validate(original_X, original_y)


def test_results_file_exists():
    path = RESULTS
    assert os.path.isfile(path), f"Missing required output file: {path}"


def test_results_format_and_values():
    path = RESULTS
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {path}, found {len(lines)}"

    p_parts = lines[0].split(',')
    assert len(p_parts) == 3, f"Line 1 should have 3 comma-separated values, found {len(p_parts)}"
    try:
        [float(x) for x in p_parts]
    except ValueError:
        pytest.fail("Line 1 does not contain valid floats")

    for i in range(1, 5):
        try:
            float(lines[i])
        except ValueError:
            pytest.fail(f"Line {i+1} does not contain a valid float: {lines[i]}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
