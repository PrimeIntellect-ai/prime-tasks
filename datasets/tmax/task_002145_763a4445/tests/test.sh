#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer ML-DATA-2024"}
BASELINE_PATH = "/app/baseline_samples.txt"
SOURCE_PATH = "/home/user/gmm_sampler.c"
BINARY_PATH = "/tmp/verified_gmm_sampler"
FLOAT_RE = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")


def two_sample_ks(a, b):
    a = np.sort(np.asarray(a, dtype=float))
    b = np.sort(np.asarray(b, dtype=float))
    points = np.sort(np.concatenate((a, b)))
    cdf_a = np.searchsorted(a, points, side="right") / len(a)
    cdf_b = np.searchsorted(b, points, side="right") / len(b)
    return float(np.max(np.abs(cdf_a - cdf_b)))


def theoretical_gmm_ks(samples):
    values = np.sort(np.asarray(samples, dtype=float))
    n = len(values)

    def normal_cdf(x, mean, sd):
        return 0.5 * (1.0 + math.erf((x - mean) / (sd * math.sqrt(2.0))))

    expected = np.asarray([
        0.3 * normal_cdf(x, -2.0, 0.5) + 0.7 * normal_cdf(x, 3.0, 1.0)
        for x in values
    ])
    upper = np.arange(1, n + 1, dtype=float) / n
    lower = np.arange(0, n, dtype=float) / n
    return float(max(np.max(upper - expected), np.max(expected - lower)))


def assert_valid_samples(samples, expected_n, baseline, threshold):
    assert isinstance(samples, list), "samples must be a list"
    assert len(samples) == expected_n, f"Expected {expected_n} samples, got {len(samples)}"
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in samples), "Every sample must be numeric"
    assert all(math.isfinite(float(x)) for x in samples), "Samples must all be finite"

    baseline_ks = two_sample_ks(samples, baseline)
    model_ks = theoretical_gmm_ks(samples)
    assert baseline_ks < threshold, f"Independent KS distance to baseline is {baseline_ks}, expected < {threshold}"
    assert model_ks < threshold, f"Samples do not follow the specified GMM: theoretical KS distance is {model_ks}"
    return baseline_ks


def parse_sampler_output(text, n, baseline):
    lines = text.splitlines()
    reported = None
    samples = None

    for line in lines:
        if "ks" in line.lower():
            vals = FLOAT_RE.findall(line)
            if vals:
                reported = float(vals[-1])
                break

    marker_index = next((i for i, line in enumerate(lines) if "sample" in line.lower()), None)
    if marker_index is not None:
        marker_line = lines[marker_index]
        tail = marker_line.split(":", 1)[1] if ":" in marker_line else ""
        sample_text = tail + "\n" + "\n".join(lines[marker_index + 1:])
        vals = [float(x) for x in FLOAT_RE.findall(sample_text)]
        if len(vals) == n:
            samples = vals

    all_vals = [float(x) for x in FLOAT_RE.findall(text)]
    if samples is None and len(all_vals) == n + 1:
        if 0.0 <= all_vals[0] <= 1.0:
            reported, samples = all_vals[0], all_vals[1:]
        elif 0.0 <= all_vals[-1] <= 1.0:
            reported, samples = all_vals[-1], all_vals[:-1]

    assert reported is not None, "Could not parse a KS statistic from the C sampler output"
    assert samples is not None, f"Could not parse exactly {n} samples from the C sampler output"
    assert math.isfinite(reported) and 0.0 <= reported <= 1.0, "C sampler emitted an invalid KS statistic"

    calculated = assert_valid_samples(samples, n, baseline, 0.06)
    assert abs(reported - calculated) <= 0.002, (
        f"C sampler reported KS {reported}, but independent calculation gives {calculated}"
    )


def test_c_sampler_exists_compiles_and_runs():
    assert os.path.exists(SOURCE_PATH), f"Missing required C source file: {SOURCE_PATH}"
    mode = os.stat(SOURCE_PATH).st_mode
    assert stat.S_ISREG(mode), "gmm_sampler.c must be a regular file"
    assert os.path.getsize(SOURCE_PATH) > 0, "gmm_sampler.c is empty"

    compiled = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", BINARY_PATH, "-lm"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert compiled.returncode == 0, f"Failed to compile gmm_sampler.c:\n{compiled.stderr}"

    run = subprocess.run(
        [BINARY_PATH, "2000"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert run.returncode == 0, f"C sampler failed when invoked:\n{run.stderr}"
    baseline = np.loadtxt(BASELINE_PATH, dtype=float)
    parse_sampler_output(run.stdout, 2000, baseline)


def test_unauthenticated_request():
    try:
        response = requests.get(f"{BASE_URL}/generate?n=100", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for unauthenticated request, got {response.status_code}"


def test_authenticated_request_and_logic():
    try:
        response = requests.get(f"{BASE_URL}/generate?n=2000", headers=AUTH_HEADER, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for authenticated request, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "ks_distance" in data, "JSON response missing 'ks_distance' key"
    assert "samples" in data, "JSON response missing 'samples' key"

    ks_distance = data["ks_distance"]
    samples = data["samples"]

    assert isinstance(ks_distance, (int, float)) and not isinstance(ks_distance, bool), "ks_distance must be a number"
    assert math.isfinite(float(ks_distance)), "ks_distance must be finite"
    assert isinstance(samples, list), "samples must be a list"
    assert len(samples) == 2000, f"Expected 2000 samples, got {len(samples)}"
    assert ks_distance < 0.05, f"KS distance {ks_distance} is too large. Expected < 0.05. Check sampling logic and baseline comparison."

    baseline = np.loadtxt(BASELINE_PATH, dtype=float)
    calculated = assert_valid_samples(samples, 2000, baseline, 0.05)
    assert abs(float(ks_distance) - calculated) <= 0.002, (
        f"Service reported KS {ks_distance}, but independent calculation gives {calculated}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
