#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import re
import subprocess

import numpy as np
import pytest

APP = '/app'
TARGET_F0 = 4.25
TARGET_GAMMA = 0.15


def test_metrics_json_exists():
    """Check if the metrics.json file exists."""
    assert os.path.isfile('/app/metrics.json'), "/app/metrics.json does not exist."


def load_metrics():
    with open('/app/metrics.json', 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("metrics.json is not a valid JSON file.")


def test_metrics_json_format_and_values():
    """Check the format of metrics.json and validate the metric threshold."""
    data = load_metrics()
    required_keys = {"mean", "ci_lower", "ci_upper"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"metrics.json is missing keys: {missing_keys}"

    mean_val = float(data['mean'])
    ci_lower = float(data['ci_lower'])
    ci_upper = float(data['ci_upper'])
    assert all(math.isfinite(x) for x in (mean_val, ci_lower, ci_upper)), "Metrics must be finite numbers."
    assert ci_lower <= mean_val <= ci_upper, f"Confidence interval is invalid: {ci_lower} <= {mean_val} <= {ci_upper} is False"

    error = abs(mean_val - TARGET_F0)
    threshold = 0.05
    assert error <= threshold, f"Absolute error of mean peak frequency ({mean_val}) from target ({TARGET_F0}) is {error:.4f}, which exceeds the threshold of {threshold}."


def test_simulator_compiled():
    """Check if the simulator was compiled to /app/simulator and is executable."""
    assert os.path.isfile('/app/simulator'), "/app/simulator executable does not exist."
    assert os.access('/app/simulator', os.X_OK), "/app/simulator is not executable."
    with open('/app/simulator', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/app/simulator is not an ELF executable."


def read_source_parameters():
    assert os.path.isfile('/app/simulator.c'), "/app/simulator.c does not exist."
    with open('/app/simulator.c', 'r') as f:
        content = f.read()

    # Preserve the original regression assertion.
    assert "double dt = 0.2;" not in content, "The buggy 'dt = 0.2' is still in simulator.c."

    dt_matches = re.findall(r'\b(?:double|float)\s+dt\s*=\s*([0-9]+(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)\s*;', content)
    steps_matches = re.findall(r'\b(?:int|long|size_t)\s+steps\s*=\s*([0-9]+)\s*;', content)
    assert dt_matches, "Could not find a numeric dt declaration in simulator.c."
    assert steps_matches, "Could not find a numeric steps declaration in simulator.c."
    dt = float(dt_matches[-1])
    steps = int(steps_matches[-1])
    assert 0 < dt <= 0.01, f"dt must be positive and no larger than 0.01, got {dt}."
    assert steps > 0, "steps must be positive."
    assert math.isclose(dt * steps, 200.0, rel_tol=0.0, abs_tol=1e-9), f"dt * steps must equal exactly 200 seconds, got {dt * steps}."
    return content, dt, steps


def test_simulator_c_fixed():
    """Check that simulator.c has the required step size and duration."""
    read_source_parameters()


def run_simulator(path, seed, steps):
    try:
        proc = subprocess.run(
            [path, str(TARGET_F0), str(TARGET_GAMMA), str(seed)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Simulator timed out for seed {seed}.")
    assert proc.returncode == 0, f"Simulator failed for seed {seed}: {proc.stderr[:500]}"
    lines = proc.stdout.splitlines()
    assert len(lines) == steps, f"Seed {seed} produced {len(lines)} samples; expected {steps}."
    try:
        values = np.asarray([float(x) for x in lines], dtype=np.float64)
    except ValueError:
        pytest.fail(f"Simulator emitted non-numeric output for seed {seed}.")
    assert np.all(np.isfinite(values)), f"Simulator emitted non-finite values for seed {seed}."
    return values


def expected_prefix(seed, dt, count):
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.restype = ctypes.c_int
    libc.srand(seed)
    rand_max = 2147483647.0
    x = 1.0
    v = 0.0
    w2 = 4.0 * math.pi * math.pi * TARGET_F0 * TARGET_F0
    result = []
    for _ in range(count):
        noise = (libc.rand() / rand_max - 0.5) * 2.0
        a = -2.0 * TARGET_GAMMA * v - w2 * x + noise
        v += a * dt
        x += v * dt
        result.append(x)
    return np.asarray(result)


def test_executed_simulation_fft_and_bootstrap(tmp_path):
    _, dt, steps = read_source_parameters()

    # Compile the submitted source independently and ensure the submitted ELF
    # actually corresponds to it.
    rebuilt = str(tmp_path / 'simulator_rebuilt')
    build = subprocess.run(
        ['gcc', '-O2', '/app/simulator.c', '-lm', '-o', rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert build.returncode == 0, f"simulator.c does not compile: {build.stderr[:1000]}"
    submitted_seed1 = run_simulator('/app/simulator', 1, steps)
    rebuilt_seed1 = run_simulator(rebuilt, 1, steps)
    assert np.array_equal(submitted_seed1, rebuilt_seed1), "/app/simulator does not match the submitted simulator.c."

    # Check the repaired numerical update against the specified oscillator.
    for seed, observed in [(1, submitted_seed1), (37, None), (100, None)]:
        if observed is None:
            observed = run_simulator('/app/simulator', seed, steps)
        expected = expected_prefix(seed, dt, min(200, steps))
        assert np.allclose(observed[:len(expected)], expected, rtol=0.0, atol=1.1e-6), f"Simulator dynamics are incorrect for seed {seed}."

    # Execute all 100 required independent trials and independently derive every
    # peak frequency from their FFTs.
    peaks = []
    for seed in range(1, 101):
        if seed == 1:
            series = submitted_seed1
        else:
            series = run_simulator('/app/simulator', seed, steps)
        power = np.abs(np.fft.rfft(series)) ** 2
        assert len(power) > 1
        peak_bin = int(np.argmax(power[1:]) + 1)  # explicitly ignore DC
        frequencies = np.fft.rfftfreq(series.size, d=dt)
        peaks.append(float(frequencies[peak_bin]))

    peaks = np.asarray(peaks)
    calculated_mean = float(np.mean(peaks))

    # Deterministic independent bootstrap with well over the required 1000 resamples.
    rng = np.random.default_rng(20240517)
    indices = rng.integers(0, len(peaks), size=(10000, len(peaks)))
    bootstrap_means = peaks[indices].mean(axis=1)
    calculated_lower, calculated_upper = np.percentile(bootstrap_means, [2.5, 97.5])

    data = load_metrics()
    reported_mean = float(data['mean'])
    reported_lower = float(data['ci_lower'])
    reported_upper = float(data['ci_upper'])

    # Allow normal three-decimal reporting and small bootstrap Monte Carlo variation.
    assert abs(reported_mean - calculated_mean) <= 0.002, f"Reported mean {reported_mean} does not match the 100 executed trials ({calculated_mean})."
    assert abs(reported_lower - calculated_lower) <= 0.01, f"Reported lower CI {reported_lower} does not match bootstrap result ({calculated_lower})."
    assert abs(reported_upper - calculated_upper) <= 0.01, f"Reported upper CI {reported_upper} does not match bootstrap result ({calculated_upper})."

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
