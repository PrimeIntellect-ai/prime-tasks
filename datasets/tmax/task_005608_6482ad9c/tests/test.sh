#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import numpy as np
from scipy.optimize import curve_fit

SCRIPT = "/home/user/analyze_spectra.py"
DATA = "/home/user/data/raw_spectra.txt"
RESULTS = "/home/user/results.json"
EXPECTED_KEYS = {"k_estimate", "ci_lower", "ci_upper"}


def load_results():
    assert os.path.isfile(RESULTS), f"Missing required file: {RESULTS}"
    with open(RESULTS, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULTS} is not valid JSON."

    assert set(results.keys()) == EXPECTED_KEYS, (
        f"JSON keys must be exactly {EXPECTED_KEYS}, found {set(results.keys())}"
    )
    for key in EXPECTED_KEYS:
        assert isinstance(results[key], (int, float)), f"Value for {key} must be a number."
        assert math.isfinite(results[key]), f"Value for {key} must be finite."
    return results


def execute_script():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f"analyze_spectra.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return load_results()


def reference_results(data_text):
    times = []
    intensities = []
    lines = [line.strip() for line in data_text.splitlines() if line.strip()]
    assert len(lines) % 2 == 0
    for i in range(0, len(lines), 2):
        assert lines[i].startswith("Time:")
        assert lines[i + 1].startswith("Intensity:")
        times.append(float(lines[i].split(":", 1)[1]))
        readings = [float(x) for x in lines[i + 1].split(":", 1)[1].split()]
        assert len(readings) == 3
        intensities.append(float(np.mean(readings)))

    t = np.asarray(times, dtype=float)
    raw = np.asarray(intensities, dtype=float)
    smooth = raw.copy()
    smooth[1:-1] = (raw[:-2] + raw[1:-1] + raw[2:]) / 3.0

    def model(x, i0, k):
        return i0 * np.exp(-k * x)

    initial = [smooth[0], 1.0]
    fitted, _ = curve_fit(model, t, smooth, p0=initial)
    predicted = model(t, *fitted)
    residuals = smooth - predicted

    np.random.seed(42)
    boot_k = []
    for _ in range(1000):
        boot_residuals = np.random.choice(residuals, size=len(t), replace=True)
        boot_data = predicted + boot_residuals
        try:
            boot_fit, _ = curve_fit(model, t, boot_data, p0=initial)
            boot_k.append(float(boot_fit[1]))
        except RuntimeError:
            continue

    assert boot_k, "Reference bootstrap unexpectedly produced no successful fits"
    lower, upper = np.percentile(boot_k, [2.5, 97.5])
    return {
        "k_estimate": float(fitted[1]),
        "ci_lower": float(lower),
        "ci_upper": float(upper),
    }


def make_probe_data():
    rng = np.random.default_rng(secrets.randbits(128))
    t = np.linspace(0.0, 5.0, 51)
    i0 = rng.uniform(70.0, 130.0)
    k = rng.uniform(0.8, 1.8)
    noise_scale = rng.uniform(1.2, 2.5)
    sensors = [i0 * np.exp(-k * t) + rng.normal(0, noise_scale, len(t)) for _ in range(3)]

    lines = []
    for i, time in enumerate(t):
        lines.append(f"Time: {time:.2f}")
        lines.append(
            f"Intensity: {sensors[0][i]:.3f} {sensors[1][i]:.3f} {sensors[2][i]:.3f}"
        )
    return "\n".join(lines) + "\n"


def assert_matches(actual, expected):
    # Four-decimal output is permitted, so allow slightly more than rounding error.
    for key in EXPECTED_KEYS:
        assert abs(actual[key] - expected[key]) <= 0.00075, (
            f"{key}={actual[key]} does not match the value {expected[key]} "
            "derived from the supplied observations"
        )


def test_complete_analysis_behavior():
    assert os.path.isfile(SCRIPT), f"Missing required script: {SCRIPT}"

    with open(DATA, "rb") as f:
        original_data = f.read()
    original_output = None

    try:
        # Execute the submitted artifact on the original observations before applying
        # all of the original verifier's format and fixed-value assertions.
        original_results = execute_script()
        with open(RESULTS, "rb") as f:
            original_output = f.read()

        k_est = original_results["k_estimate"]
        ci_lower = original_results["ci_lower"]
        ci_upper = original_results["ci_upper"]
        assert ci_lower <= k_est <= ci_upper, (
            f"Confidence interval [{ci_lower}, {ci_upper}] does not contain the estimate {k_est}."
        )
        assert abs(k_est - 2.5539) < 0.05, (
            f"k_estimate {k_est} is out of expected range (expected ~2.5539)."
        )
        assert abs(ci_lower - 2.4544) < 0.05, (
            f"ci_lower {ci_lower} is out of expected range (expected ~2.4544)."
        )
        assert abs(ci_upper - 2.6582) < 0.05, (
            f"ci_upper {ci_upper} is out of expected range (expected ~2.6582)."
        )

        # Replace the observations with an unpredictable valid dataset and derive the
        # expected fit and seeded residual-bootstrap interval independently.
        probe_data = make_probe_data()
        expected = reference_results(probe_data)
        with open(DATA, "w") as f:
            f.write(probe_data)
        probe_results = execute_script()
        assert_matches(probe_results, expected)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_output is not None:
            with open(RESULTS, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
