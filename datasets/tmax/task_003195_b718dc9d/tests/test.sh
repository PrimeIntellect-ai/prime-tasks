#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import sys

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

RESULTS_FILE = "/home/user/results.json"
SCRIPT_FILE = "/home/user/analyze.py"
DATA_DIR = "/home/user/profiling_data"
SCALES = (1, 2, 4, 8)


def load_results():
    with open(RESULTS_FILE, "r") as f:
        return json.load(f)


def run_script():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        check=True,
        timeout=60,
    )
    assert os.path.isfile(RESULTS_FILE), \
        f"The script did not create {RESULTS_FILE}"
    return load_results()


def test_00_script_executes_and_uses_csv_inputs():
    assert os.path.isfile(SCRIPT_FILE), f"Missing required script {SCRIPT_FILE}"

    paths = {n: os.path.join(DATA_DIR, f"rank_{n}.csv") for n in SCALES}
    original_data = {n: open(path, "rb").read() for n, path in paths.items()}

    rng = np.random.default_rng(secrets.randbits(64))
    probe_p = rng.uniform(0.30, 0.60)
    probe_t1 = rng.uniform(80.0, 120.0)
    probe_arrays = {}

    for n in SCALES:
        target_mean = probe_t1 * ((1.0 - probe_p) + probe_p / n)
        noise = rng.normal(0.0, 0.5 + 0.1 * n, size=1000)
        noise -= noise.mean()
        probe_arrays[n] = target_mean + noise

    try:
        for n, values in probe_arrays.items():
            np.savetxt(paths[n], values, fmt="%.10f", header="latency", comments="")

        probe_results = run_script()
        assert "parallel_fraction" in probe_results
        assert "wasserstein_distance" in probe_results

        expected_w = wasserstein_distance(probe_arrays[1], probe_arrays[8])
        assert math.isclose(
            probe_results["parallel_fraction"], probe_p,
            rel_tol=0.0, abs_tol=1e-3
        ), f"parallel_fraction was not calculated from the probe CSV data"
        assert math.isclose(
            probe_results["wasserstein_distance"], expected_w,
            rel_tol=1e-7, abs_tol=1e-5
        ), f"wasserstein_distance was not calculated from the probe CSV data"
    finally:
        for n, contents in original_data.items():
            with open(paths[n], "wb") as f:
                f.write(contents)
        # Leave results.json corresponding to the task's original input files.
        run_script()


def test_results_file_exists():
    """Check if the results.json file was created."""
    assert os.path.isfile(RESULTS_FILE), f"The file {RESULTS_FILE} does not exist. Did you run your script?"


def test_results_content_and_accuracy():
    """Parse results.json and verify the calculated metrics."""
    assert os.path.isfile(RESULTS_FILE), f"Missing {RESULTS_FILE}"

    with open(RESULTS_FILE, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_FILE} does not contain valid JSON.")

    assert "parallel_fraction" in results, f"Key 'parallel_fraction' is missing from {RESULTS_FILE}"
    assert "wasserstein_distance" in results, f"Key 'wasserstein_distance' is missing from {RESULTS_FILE}"

    p_frac = results["parallel_fraction"]
    w_dist = results["wasserstein_distance"]

    assert isinstance(p_frac, (int, float)), "parallel_fraction must be a number"
    assert isinstance(w_dist, (int, float)), "wasserstein_distance must be a number"

    expected_p_frac = 0.8
    expected_w_dist = 70.0

    assert math.isclose(p_frac, expected_p_frac, abs_tol=0.05), \
        f"parallel_fraction {p_frac} is not within the expected range (expected ~{expected_p_frac})"

    assert math.isclose(w_dist, expected_w_dist, abs_tol=2.0), \
        f"wasserstein_distance {w_dist} is not within the expected range (expected ~{expected_w_dist})"

    rank_1 = np.loadtxt(os.path.join(DATA_DIR, "rank_1.csv"), skiprows=1)
    rank_8 = np.loadtxt(os.path.join(DATA_DIR, "rank_8.csv"), skiprows=1)
    derived_w_dist = wasserstein_distance(rank_1, rank_8)
    assert math.isclose(w_dist, derived_w_dist, rel_tol=1e-7, abs_tol=1e-5), \
        "wasserstein_distance does not match the original CSV distributions"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
