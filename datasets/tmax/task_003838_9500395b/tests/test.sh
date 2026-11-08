#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import time
import pytest

SCRIPT = "/home/user/simulate.sh"


def run_simulation(weight):
    result = subprocess.run(
        [SCRIPT, format(weight, ".12g")],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"simulate.sh failed with return code {result.returncode}: {result.stderr}"
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"simulate.sh output is not a single float: {output!r}")
    assert math.isfinite(value), f"simulate.sh produced a non-finite value: {value}"
    assert 0.0 <= value <= 1.0, f"simulate.sh produced an invalid fraction: {value}"
    return value


def test_results_file():
    results_file = "/home/user/results.txt"
    assert os.path.exists(results_file), "results.txt not found"

    with open(results_file, "r") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    # Preserve the original checks and enforce the instruction's exact format.
    assert len(lines) >= 2, "results.txt needs at least 2 lines"
    assert len(raw_lines) == 2 and len(lines) == 2, "results.txt must contain exactly two non-empty lines"

    try:
        w_A = float(lines[0])
        diff = float(lines[1])
    except ValueError:
        pytest.fail("results.txt contains non-numeric values")

    assert 0.29 <= w_A <= 0.31, f"Incorrect weight w_A: {w_A}. Expected 0.3"
    assert 0.0 <= diff <= 0.02, f"Monte Carlo difference too large or invalid: {diff}"
    assert math.isfinite(w_A) and math.isfinite(diff), "results.txt values must be finite"
    assert abs(w_A - 0.3) <= 1e-12, f"Analytical weight must be exactly 0.3, got {w_A}"
    # A fraction from 100,000 trials, and hence its distance from 0.40, lies on this grid.
    assert abs(diff * 100000 - round(diff * 100000)) <= 1e-6, \
        "The reported difference is not consistent with 100,000 simulated bases"


def test_simulate_script_exists_and_executable():
    assert os.path.exists(SCRIPT), "simulate.sh not found"
    assert os.access(SCRIPT, os.X_OK), "simulate.sh is not executable"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), "simulate.sh must be a regular executable file"


def test_simulate_script_execution():
    # Preserve the original fixed-input execution and range assertion.
    try:
        simulated_gc = run_simulation(0.3)
        assert 0.35 <= simulated_gc <= 0.45, \
            f"Simulated GC-content {simulated_gc} is out of expected range for w_A=0.3"
    except Exception as e:
        pytest.fail(f"Failed to execute simulate.sh or parse its output: {e}")


def test_simulation_uses_weight_and_matches_derived_expectations():
    # The expected GC fraction is derived independently as 0.25 + 0.50*w_A.
    # Include secret inputs so a fixed-output or fixed-subset implementation cannot pass.
    rng = secrets.SystemRandom()
    weights = [0.0, 1.0, rng.uniform(0.08, 0.92), rng.uniform(0.08, 0.92)]
    for weight in weights:
        observed = run_simulation(weight)
        expected = 0.25 + 0.50 * weight
        assert abs(observed - expected) <= 0.015, \
            f"For w_A={weight}, got {observed}; expected a simulation near {expected}"
        assert abs(observed * 100000 - round(observed * 100000)) <= 1e-6, \
            "Output is not a possible GC count divided by 100,000"


def test_simulation_is_random_with_100000_trial_scale():
    rng = secrets.SystemRandom()
    weight = rng.uniform(0.2, 0.8)
    expected = 0.25 + 0.50 * weight
    values = []

    # Spacing invocations avoids accidental identical seeds from awk's second-resolution srand().
    for i in range(7):
        if i:
            time.sleep(1.05)
        values.append(run_simulation(weight))

    assert len(set(values)) > 1, "simulate.sh appears deterministic rather than Monte Carlo"
    mean = sum(values) / len(values)
    assert abs(mean - expected) <= 0.008, \
        f"Repeated simulations have mean {mean}, expected near {expected}"

    sample_variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
    expected_variance = expected * (1.0 - expected) / 100000.0
    assert 0.02 * expected_variance <= sample_variance <= 15.0 * expected_variance, \
        f"Observed variance {sample_variance} is inconsistent with 100,000 random bases"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
