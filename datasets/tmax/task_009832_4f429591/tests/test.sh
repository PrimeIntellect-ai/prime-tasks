#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

EXE = "/home/user/bin/solver"
CSV_PATH = "/home/user/data/raw_peaks.csv"
SCRIPT = "/home/user/process_spectra.py"
JSON_PATH = "/home/user/data/summary.json"


def expected_solver_results():
    rows = []
    max_iter = 0
    for i in range(1, 11):
        M = i * 8.5
        E = M
        epsilon = 0.15
        iterations = 0
        while True:
            iterations += 1
            E_next = M + epsilon * math.sin(E)
            if abs(E_next - E) < 1e-7:
                break
            E = E_next
            assert iterations < 1000
        max_iter = max(max_iter, iterations)
        rows.append((100.0 / i, E))
    return max_iter, rows


def read_peaks():
    with open(CSV_PATH, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["intensity", "frequency"], \
            f"Header missing or incorrect in {CSV_PATH}"
        rows = [(float(row["intensity"]), float(row["frequency"])) for row in reader]
    assert rows, f"{CSV_PATH} does not contain enough data"
    return rows


def expected_distance(rows):
    grid = np.linspace(0, 100, 1000)
    clean = np.zeros(1000, dtype=float)
    for intensity, frequency in rows:
        clean += intensity * np.exp(-((grid - frequency) ** 2) / (2 * 2.0 ** 2))

    np.random.seed(42)
    noisy = clean + np.random.uniform(0, 0.5, size=1000)
    clean = clean / clean.sum()
    noisy = noisy / noisy.sum()
    return round(float(wasserstein_distance(
        grid, grid, u_weights=clean, v_weights=noisy
    )), 6)


def run_processor():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", check=True,
        timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert os.path.isfile(JSON_PATH), f"JSON summary not found at {JSON_PATH}"


def check_summary(expected_iterations, expected_w_dist):
    with open(JSON_PATH) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not a valid JSON file")

    assert set(data.keys()) == {"convergence_max_iterations", "wasserstein_distance"}, \
        "summary.json must contain exactly the two required keys"
    assert data["convergence_max_iterations"] == expected_iterations, \
        f"Expected convergence_max_iterations to be {expected_iterations}, got {data['convergence_max_iterations']}"

    actual_w_dist = data["wasserstein_distance"]
    assert isinstance(actual_w_dist, (int, float)), \
        "wasserstein_distance must be a number"
    assert math.isclose(actual_w_dist, expected_w_dist, abs_tol=5e-7), \
        f"Expected wasserstein_distance to be {expected_w_dist}, got {actual_w_dist}"


def test_complete_solver_and_processing_pipeline():
    # Preserve the original existence and executable checks, and ensure the
    # submitted solver is a compiled native executable rather than a shell stub.
    assert os.path.isfile(EXE), f"Executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE} is not a compiled ELF executable"

    assert os.path.isfile(SCRIPT), f"Python script not found at {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Python script at {SCRIPT} is empty"

    # Execute the submitted solver from a clean output state and parse the
    # convergence statistic from its actual stdout.
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [EXE], check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    match = re.search(r"Solver finished\. Max convergence iterations:\s*(\d+)", result.stdout)
    assert match, "Solver stdout did not contain the required convergence message"
    reported_iterations = int(match.group(1))

    assert os.path.isfile(CSV_PATH), f"Data file not found at {CSV_PATH}"
    generated_rows = read_peaks()
    expected_iterations, expected_rows = expected_solver_results()
    assert reported_iterations == expected_iterations, \
        f"Solver reported {reported_iterations} iterations; expected {expected_iterations}"
    assert len(generated_rows) == len(expected_rows) == 10
    for actual, expected in zip(generated_rows, expected_rows):
        assert math.isclose(actual[0], expected[0], rel_tol=1e-5, abs_tol=1e-5)
        assert math.isclose(actual[1], expected[1], rel_tol=1e-5, abs_tol=1e-5)

    generated_csv = open(CSV_PATH, "rb").read()

    # Exercise the processing script on independently supplied peak data so a
    # hardcoded summary or empty script cannot pass.
    probe_rows = [(17.25, 4.5), (3.75, 41.125), (92.0, 88.75)]
    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["intensity", "frequency"])
            writer.writerows(probe_rows)
        run_processor()
        check_summary(reported_iterations, expected_distance(probe_rows))
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(generated_csv)

    # Re-run on the solver's real output and verify the required final state.
    run_processor()
    check_summary(reported_iterations, expected_distance(generated_rows))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
