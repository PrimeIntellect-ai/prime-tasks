#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import pytest
from scipy.stats import wasserstein_distance

PARAMS_PATH = '/home/user/params.txt'
DIST_PATH = '/home/user/distance.txt'
DATA_PATH = '/home/user/data.txt'
TEST_SCRIPT = '/home/user/test_fit.py'


def load_params():
    assert os.path.isfile(PARAMS_PATH), f"File {PARAMS_PATH} does not exist."
    with open(PARAMS_PATH, 'r') as f:
        content = f.read().strip()
    parts = content.split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated values in {PARAMS_PATH}, got {len(parts)}."
    try:
        values = tuple(map(float, parts))
    except ValueError:
        pytest.fail(f"Could not parse parameters as floats: {content}")
    assert all(np.isfinite(values)), f"Parameters must be finite, got {values}"
    return values


def test_params_file():
    w, mu1, mu2 = load_params()
    assert 0 <= w <= 1, f"Expected w to be between 0 and 1, got {w}"
    assert mu1 < mu2, f"Expected mu1 < mu2, got mu1={mu1}, mu2={mu2}"

    # Keep the original approximate-value assertions.
    assert abs(w - 0.3) < 0.1, f"w is too far from expected ~0.3, got {w}"
    assert abs(mu1 - (-2.0)) < 0.5, f"mu1 is too far from expected ~-2.0, got {mu1}"
    assert abs(mu2 - 2.0) < 0.5, f"mu2 is too far from expected ~2.0, got {mu2}"

    # Verify that the submitted values actually solve the empirical moment system.
    data = np.loadtxt(DATA_PATH)
    empirical = np.array([np.mean(data), np.mean(data**2), np.mean(data**3)])
    modeled = np.array([
        w * mu1 + (1 - w) * mu2,
        w * (mu1**2 + 1.0) + (1 - w) * (mu2**2 + 1.0),
        w * (mu1**3 + 3.0 * mu1) + (1 - w) * (mu2**3 + 3.0 * mu2),
    ])
    assert np.max(np.abs(modeled - empirical)) < 1e-3, \
        f"Parameters do not solve the empirical moment equations: residuals={modeled - empirical}"


def test_distance_file_and_independent_distance():
    assert os.path.isfile(DIST_PATH), f"File {DIST_PATH} does not exist."
    with open(DIST_PATH, 'r') as f:
        content = f.read().strip()
    try:
        reported = float(content)
    except ValueError:
        pytest.fail(f"Could not parse distance as float: {content}")

    assert np.isfinite(reported), f"Distance must be finite, got {reported}"
    assert reported < 0.1, f"Expected Wasserstein distance < 0.1, got {reported}"

    # Independently generate 100,000 samples and recompute the Wasserstein distance.
    w, mu1, mu2 = load_params()
    data = np.loadtxt(DATA_PATH)
    rng = np.random.default_rng(731942)
    choose_first = rng.random(100000) < w
    fitted = np.empty(100000)
    fitted[choose_first] = rng.normal(mu1, 1.0, int(choose_first.sum()))
    fitted[~choose_first] = rng.normal(mu2, 1.0, int((~choose_first).sum()))
    recomputed = wasserstein_distance(data, fitted)

    assert recomputed < 0.1, \
        f"Independently recomputed Wasserstein distance is too large: {recomputed}"
    assert abs(reported - recomputed) < 0.03, \
        f"Reported distance {reported} is inconsistent with recomputed distance {recomputed}"


def test_test_fit_script():
    assert os.path.isfile(TEST_SCRIPT), f"Script {TEST_SCRIPT} does not exist."

    # It must succeed for the fitted parameters.
    result = subprocess.run(
        ['python3', TEST_SCRIPT], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, \
        f"{TEST_SCRIPT} failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    # It must also be a real regression test: deliberately bad parameters must
    # cause the requested AssertionError rather than a no-op successful exit.
    with open(PARAMS_PATH, 'rb') as f:
        original_params = f.read()
    try:
        with open(PARAMS_PATH, 'w') as f:
            f.write('0.5,100.0,101.0\n')
        bad = subprocess.run(
            ['python3', TEST_SCRIPT], capture_output=True, text=True, timeout=60
        )
    finally:
        with open(PARAMS_PATH, 'wb') as f:
            f.write(original_params)

    combined = bad.stdout + '\n' + bad.stderr
    assert bad.returncode != 0, \
        f"{TEST_SCRIPT} incorrectly accepted deliberately bad parameters."
    assert 'AssertionError' in combined, \
        f"{TEST_SCRIPT} must raise AssertionError for a distance above 0.1. Output:\n{combined}"
TEST_EOF

# Remove stale/self-reported outputs and require the repaired fitting artifact to
# recreate them when actually executed.
rm -f /home/user/params.txt /home/user/distance.txt

if timeout 60 python3 /home/user/fit_gmm.py >/tmp/fit_gmm.stdout 2>/tmp/fit_gmm.stderr \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/fit_gmm.stdout 2>/dev/null || true
    cat /tmp/fit_gmm.stderr 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
