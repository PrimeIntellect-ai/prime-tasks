#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import subprocess

import numpy as np
import pytest

RAW_PATH = "/home/user/raw_observations.txt"
CLEAN_PATH = "/home/user/cleaned_dataset.csv"
RESULTS_PATH = "/home/user/results.json"
PIPELINE_PATH = "/home/user/run_pipeline.sh"

# A verifier-private input prevents a pipeline containing constants for the
# image's original dataset from passing.
rng = np.random.default_rng(773)
HIDDEN_X = np.linspace(-1.5, 8.5, 43)
HIDDEN_Y1 = 1.75 * HIDDEN_X - 0.60 + rng.normal(0.0, 0.38, HIDDEN_X.size)
HIDDEN_Y2 = 1.75 * HIDDEN_X - 0.35 + rng.normal(0.0, 0.45, HIDDEN_X.size)
HIDDEN_S1 = {float(f"{x:.4f}"): float(f"{y:.4f}") for x, y in zip(HIDDEN_X, HIDDEN_Y1)}
HIDDEN_S2 = {float(f"{x:.4f}"): float(f"{y:.4f}") for x, y in zip(HIDDEN_X, HIDDEN_Y2)}


def test_run_pipeline_exists_and_executable():
    assert os.path.exists(PIPELINE_PATH), f"{PIPELINE_PATH} does not exist."
    assert os.path.isfile(PIPELINE_PATH), f"{PIPELINE_PATH} is not a file."
    assert os.access(PIPELINE_PATH, os.X_OK), f"{PIPELINE_PATH} is not executable."


def test_run_pipeline_on_private_input():
    lines = []
    for x in sorted(HIDDEN_S1):
        lines.append(f"S1,{x:.4f},{HIDDEN_S1[x]:.4f}\n")
        lines.append(f"S2,{x:.4f},{HIDDEN_S2[x]:.4f}\n")
    np.random.default_rng(991).shuffle(lines)

    with open(RAW_PATH, "w") as f:
        f.writelines(lines)

    for path in (CLEAN_PATH, RESULTS_PATH):
        if os.path.exists(path):
            os.remove(path)

    try:
        completed = subprocess.run(
            [PIPELINE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=300,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"run_pipeline.sh timed out after 300 seconds. Output:\n{exc.stdout or ''}")

    assert completed.returncode == 0, (
        f"run_pipeline.sh exited with status {completed.returncode}. Output:\n"
        f"{completed.stdout}"
    )


def test_cleaned_dataset_csv():
    assert os.path.exists(CLEAN_PATH), f"{CLEAN_PATH} does not exist."
    assert os.path.exists(RAW_PATH), f"Original {RAW_PATH} is missing."

    s1, s2 = {}, {}
    with open(RAW_PATH, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 3:
                sensor, x, y = parts[0], float(parts[1]), float(parts[2])
                if sensor == "S1":
                    s1[x] = y
                elif sensor == "S2":
                    s2[x] = y

    assert s1 == HIDDEN_S1, "The pipeline modified or replaced the private S1 input."
    assert s2 == HIDDEN_S2, "The pipeline modified or replaced the private S2 input."
    x_sorted = sorted(s1.keys())

    with open(CLEAN_PATH, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert len(header) >= 3, "CSV header should have at least 3 columns"
        rows = list(reader)

    assert len(rows) == len(x_sorted), (
        f"Expected {len(x_sorted)} rows in CSV, found {len(rows)}"
    )

    for idx, row in enumerate(rows):
        x_val = float(row[0])
        y1_val = float(row[1])
        y2_val = float(row[2])
        expected_x = x_sorted[idx]
        assert math.isclose(x_val, expected_x, rel_tol=1e-4), (
            f"Row {idx + 1}: x expected {expected_x}, got {x_val}"
        )
        assert math.isclose(y1_val, s1[expected_x], rel_tol=1e-4), (
            f"Row {idx + 1}: y1 expected {s1[expected_x]}, got {y1_val}"
        )
        assert math.isclose(y2_val, s2[expected_x], rel_tol=1e-4), (
            f"Row {idx + 1}: y2 expected {s2[expected_x]}, got {y2_val}"
        )


def independently_compute_results():
    try:
        from scipy.stats import ttest_rel
        import emcee
    except ImportError as exc:
        pytest.fail(f"Pipeline did not make a required dependency available: {exc}")

    xs = np.array(sorted(HIDDEN_S1), dtype=float)
    y1 = np.array([HIDDEN_S1[x] for x in xs], dtype=float)
    y2 = np.array([HIDDEN_S2[x] for x in xs], dtype=float)
    p_value = float(ttest_rel(y1, y2).pvalue)

    def log_probability(theta):
        m, c = theta
        if not (0.0 <= m <= 5.0 and -5.0 <= c <= 5.0):
            return -np.inf
        residual = y1 - (m * xs + c)
        return -0.5 * np.sum((residual / 0.5) ** 2)

    np.random.seed(42)
    initial = np.array([2.0, 1.0]) + 0.01 * np.random.randn(10, 2)
    sampler = emcee.EnsembleSampler(10, 2, log_probability)
    sampler.run_mcmc(initial, 2000, progress=False)
    posterior = sampler.get_chain(discard=500, flat=True)

    return p_value, float(np.mean(posterior[:, 0])), float(np.mean(posterior[:, 1]))


def test_results_json():
    assert os.path.exists(RESULTS_PATH), f"{RESULTS_PATH} does not exist."

    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} is not valid JSON.")

    assert "p_value" in results, "Missing 'p_value' in results.json"
    assert "m_mean" in results, "Missing 'm_mean' in results.json"
    assert "c_mean" in results, "Missing 'c_mean' in results.json"

    for key in ("p_value", "m_mean", "c_mean"):
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), (
            f"{key} must be numeric"
        )
        assert math.isfinite(float(results[key])), f"{key} must be finite"

    expected_p, expected_m, expected_c = independently_compute_results()
    assert math.isclose(float(results["p_value"]), expected_p, rel_tol=1e-10, abs_tol=1e-14), (
        f"p_value {results['p_value']} does not match the independently recomputed paired t-test value {expected_p}"
    )
    assert math.isclose(float(results["m_mean"]), expected_m, rel_tol=1e-10, abs_tol=1e-10), (
        f"m_mean {results['m_mean']} does not match the independently reproduced MCMC value {expected_m}"
    )
    assert math.isclose(float(results["c_mean"]), expected_c, rel_tol=1e-10, abs_tol=1e-10), (
        f"c_mean {results['c_mean']} does not match the independently reproduced MCMC value {expected_c}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
