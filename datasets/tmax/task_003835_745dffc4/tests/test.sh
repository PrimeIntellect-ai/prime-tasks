#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import random
import subprocess
import sys

import numpy as np
from scipy.stats import ks_2samp, wasserstein_distance

SIMULATE_PATH = "/home/user/simulate.py"
COMPARE_PATH = "/home/user/compare.py"
JSON_PATH = "/home/user/comparison.json"


def load_simulate():
    name = "submitted_simulate_fresh"
    sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(name, SIMULATE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def baseline_reference(n, seed):
    rng = random.Random(seed)
    return np.array([
        sum(rng.gauss(0, 1) for _ in range(100))
        for _ in range(n)
    ])


def test_final_state():
    # Preserve the original source and artifact checks.
    assert os.path.isfile(SIMULATE_PATH), f"File {SIMULATE_PATH} does not exist."
    with open(SIMULATE_PATH, "r") as f:
        simulate_source = f.read()
    assert "def simulate_v1" in simulate_source, "simulate_v1 function is missing."
    assert "def simulate_v2" in simulate_source, "simulate_v2 function is missing."
    assert "scale=1.05" not in simulate_source, "The bug (scale=1.05) in simulate_v2 was not fixed."

    assert os.path.isfile(COMPARE_PATH), f"File {COMPARE_PATH} does not exist."
    with open(COMPARE_PATH, "r") as f:
        compare_source = f.read()
    assert "scipy" in compare_source, "compare.py must use scipy.stats."
    assert "wasserstein_distance" in compare_source, "compare.py must compute Wasserstein distance."
    assert "ks_2samp" in compare_source, "compare.py must compute the 2-sample KS test."

    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} does not exist."

    # Ensure the trusted baseline was not replaced or weakened.
    sim = load_simulate()
    assert callable(getattr(sim, "simulate_v1", None))
    assert callable(getattr(sim, "simulate_v2", None))
    for seed in (0, 42, 913):
        actual = np.asarray(sim.simulate_v1(64, seed=seed))
        expected = baseline_reference(64, seed)
        assert actual.shape == (64,)
        assert np.array_equal(actual, expected), "simulate_v1 no longer matches the trusted baseline."

    # Exercise the fixed implementation directly. A 100-step unit-normal walk
    # has standard deviation 10; the original 1.05 scale fails this check.
    v2_large = np.asarray(sim.simulate_v2(50000, seed=123), dtype=float)
    assert v2_large.shape == (50000,), "simulate_v2 returned the wrong shape."
    assert np.all(np.isfinite(v2_large)), "simulate_v2 returned non-finite values."
    assert abs(float(np.std(v2_large)) - 10.0) < 0.15, \
        "simulate_v2 does not have the variance of a 100-step unit-normal random walk."

    # Delete the self-reported result and require compare.py to recreate it.
    os.remove(JSON_PATH)
    completed = subprocess.run(
        [sys.executable, COMPARE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, \
        f"compare.py failed:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.isfile(JSON_PATH), "compare.py did not create comparison.json."

    with open(JSON_PATH, "r") as f:
        data = json.load(f)
    assert set(data) == {"wasserstein_distance", "ks_pvalue"}, \
        "comparison.json must have exactly the required keys."
    wasserstein = data["wasserstein_distance"]
    pvalue = data["ks_pvalue"]
    assert isinstance(wasserstein, (int, float)) and not isinstance(wasserstein, bool), \
        "wasserstein_distance must be a float."
    assert isinstance(pvalue, (int, float)) and not isinstance(pvalue, bool), \
        "ks_pvalue must be a float."
    assert math.isfinite(wasserstein) and math.isfinite(pvalue)

    # Independently derive the required answers from fresh function calls.
    sim = load_simulate()
    baseline = np.asarray(sim.simulate_v1(10000, seed=42), dtype=float)
    candidate = np.asarray(sim.simulate_v2(10000, seed=42), dtype=float)
    assert baseline.shape == (10000,) and candidate.shape == (10000,)
    expected_wasserstein = float(wasserstein_distance(baseline, candidate))
    expected_pvalue = float(ks_2samp(baseline, candidate).pvalue)
    assert math.isclose(float(wasserstein), expected_wasserstein, rel_tol=1e-10, abs_tol=1e-12), \
        "comparison.json contains an incorrect Wasserstein distance."
    assert math.isclose(float(pvalue), expected_pvalue, rel_tol=1e-10, abs_tol=1e-12), \
        "comparison.json contains an incorrect KS p-value."

    # Preserve the original acceptance criteria.
    assert wasserstein < 0.5, \
        f"Wasserstein distance {wasserstein} is too high, bug likely not fixed properly."
    assert pvalue > 0.01, \
        f"KS p-value {pvalue} is too low, distributions do not match."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
