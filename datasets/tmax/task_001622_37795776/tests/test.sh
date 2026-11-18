#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
from scipy.stats import gaussian_kde

SCRIPT = "/home/user/analyze_diffusion.py"
METRICS = "/home/user/diffusion_metrics.json"


def test_analyze_script_exists_and_runs():
    assert os.path.isfile(SCRIPT), "The file /home/user/analyze_diffusion.py does not exist."
    if os.path.exists(METRICS):
        os.remove(METRICS)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        "analyze_diffusion.py failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(METRICS), "The script did not generate /home/user/diffusion_metrics.json."


def test_diffusion_metrics_exists():
    assert os.path.isfile(METRICS), "The file /home/user/diffusion_metrics.json does not exist."


def test_diffusion_metrics_format():
    with open(METRICS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file /home/user/diffusion_metrics.json is not valid JSON."

    assert "kde_values" in data, "Missing 'kde_values' in JSON."
    assert "analytical_values" in data, "Missing 'analytical_values' in JSON."
    assert "max_diff" in data, "Missing 'max_diff' in JSON."

    assert isinstance(data["kde_values"], list), "'kde_values' should be a list."
    assert len(data["kde_values"]) == 5, "'kde_values' should have exactly 5 elements."
    assert all(isinstance(x, (int, float)) for x in data["kde_values"]), "All 'kde_values' must be numbers."

    assert isinstance(data["analytical_values"], list), "'analytical_values' should be a list."
    assert len(data["analytical_values"]) == 5, "'analytical_values' should have exactly 5 elements."
    assert all(isinstance(x, (int, float)) for x in data["analytical_values"]), "All 'analytical_values' must be numbers."

    assert isinstance(data["max_diff"], (int, float)), "'max_diff' should be a number."


def independently_compute_metrics():
    np.random.seed(42)
    steps = np.random.uniform(-np.sqrt(3.0), np.sqrt(3.0), size=(100000, 100))
    final_positions = np.sum(steps, axis=1)
    x_eval = np.array([-10.0, -5.0, 0.0, 5.0, 10.0])
    kde_values = gaussian_kde(final_positions)(x_eval)

    L = 100.0
    n_grid = 4096
    dx = 2.0 * L / n_grid
    x = np.arange(n_grid) * dx - L
    k = 2.0 * np.pi * np.fft.fftfreq(n_grid, d=dx)
    phi = np.sinc(np.sqrt(3.0) * k / np.pi)
    characteristic = phi ** 100
    analytical_pdf = np.fft.fftshift(np.fft.ifft(characteristic).real) / dx
    analytical_values = np.interp(x_eval, x, analytical_pdf)
    max_diff = np.max(np.abs(kde_values - analytical_values))
    return kde_values, analytical_values, float(max_diff)


def test_diffusion_metrics_values():
    with open(METRICS, "r") as f:
        data = json.load(f)

    kde_vals = data["kde_values"]
    ana_vals = data["analytical_values"]
    max_diff = data["max_diff"]

    expected_approx = [0.02419, 0.03520, 0.03989, 0.03520, 0.02419]
    for i, (val, expected) in enumerate(zip(ana_vals, expected_approx)):
        assert math.isclose(val, expected, abs_tol=1e-2), f"Analytical value at index {i} ({val}) is not close to expected ~{expected}."

    computed_max_diff = max(abs(k - a) for k, a in zip(kde_vals, ana_vals))
    assert math.isclose(max_diff, computed_max_diff, abs_tol=1e-5), f"max_diff {max_diff} does not match computed max absolute difference {computed_max_diff}."

    expected_kde, expected_analytical, expected_max_diff = independently_compute_metrics()
    assert np.all(np.isfinite(np.asarray(kde_vals, dtype=float))), "KDE values must be finite."
    assert np.all(np.isfinite(np.asarray(ana_vals, dtype=float))), "Analytical values must be finite."
    assert math.isfinite(float(max_diff)), "max_diff must be finite."
    assert np.allclose(kde_vals, expected_kde, rtol=1e-7, atol=1e-8), (
        f"KDE values do not match the independently reproduced seeded simulation: {kde_vals}"
    )
    assert np.allclose(ana_vals, expected_analytical, rtol=1e-7, atol=1e-8), (
        f"Analytical values do not match the independently computed FFT solution: {ana_vals}"
    )
    assert math.isclose(float(max_diff), expected_max_diff, rel_tol=1e-7, abs_tol=1e-8), (
        f"max_diff {max_diff} does not match the independently computed value {expected_max_diff}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
