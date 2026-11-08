#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import subprocess
import pytest


def test_venv_and_numpy():
    venv_path = "/home/user/sim_env"
    assert os.path.isdir(venv_path), "Virtual environment not found at /home/user/sim_env"

    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), "Python executable not found in the virtual environment"

    # Check if numpy is installed in the virtual environment
    result = subprocess.run([python_bin, "-c", "import numpy"], capture_output=True)
    assert result.returncode == 0, "numpy is not installed in the virtual environment"


def test_script_executable():
    script_path = "/home/user/evaluate_runs.sh"
    assert os.path.isfile(script_path), f"{script_path} not found"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"


def test_regression_results_and_best_run():
    script_path = "/home/user/evaluate_runs.sh"
    ref_file = "/home/user/data/reference.txt"
    cand_dir = "/home/user/data/candidates"
    csv_file = "/home/user/regression_results.csv"
    best_file = "/home/user/best_run.txt"

    assert os.path.isfile(script_path), f"{script_path} not found"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"
    assert os.path.isfile(ref_file), f"Reference file missing: {ref_file}"
    assert os.path.isdir(cand_dir), f"Candidates directory missing: {cand_dir}"

    # Remove any pre-generated artifacts and require the submitted script to recreate them.
    for output in (csv_file, best_file):
        if os.path.lexists(output):
            os.remove(output)

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{script_path} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(csv_file), f"Results CSV missing: {csv_file}"
    assert os.path.isfile(best_file), f"Best run file missing: {best_file}"

    # Read reference data
    with open(ref_file, "r") as f:
        x = [float(line.strip()) for line in f if line.strip()]

    n = len(x)
    assert n > 0, "Reference file is empty"

    mean_x = sum(x) / n
    var_x = sum((xi - mean_x) ** 2 for xi in x)

    expected_results = {}
    best_score = float('inf')
    best_run = ""

    # Compute expected regression results for each candidate
    for cand in os.listdir(cand_dir):
        if not cand.endswith(".txt"):
            continue
        with open(os.path.join(cand_dir, cand), "r") as f:
            y = [float(line.strip()) for line in f if line.strip()]

        assert len(y) == n, f"Candidate {cand} has different number of lines than reference"

        mean_y = sum(y) / n
        cov_xy = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))

        m = cov_xy / var_x
        c = mean_y - m * mean_x
        score = (m - 1.0) ** 2 + (c - 0.0) ** 2

        expected_results[cand] = (m, c, score)
        if score < best_score:
            best_score = score
            best_run = cand

    # Read actual CSV and enforce the required header and six-decimal formatting.
    actual_results = {}
    float_format = re.compile(r"[+-]?\d+\.\d{6}")
    with open(csv_file, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"Results CSV is empty: {csv_file}")
        assert header == ["filename", "slope", "intercept", "score"], (
            f"Incorrect CSV header: {header}"
        )

        for row in reader:
            assert len(row) == 4, f"Invalid CSV row: {row}"
            assert row[0], f"Missing filename in CSV row: {row}"
            assert row[0] not in actual_results, f"Duplicate candidate row in CSV: {row[0]}"
            for value in row[1:]:
                assert float_format.fullmatch(value), (
                    f"Float is not formatted to exactly 6 decimal places: {value}"
                )
            try:
                actual_results[row[0]] = (float(row[1]), float(row[2]), float(row[3]))
            except ValueError:
                pytest.fail(f"Invalid float format in CSV row: {row}")

    assert len(actual_results) == len(expected_results), "CSV does not contain entries for all candidates"

    # Validate CSV contents
    for cand, (exp_m, exp_c, exp_s) in expected_results.items():
        assert cand in actual_results, f"Candidate {cand} missing from {csv_file}"
        act_m, act_c, act_s = actual_results[cand]

        assert abs(act_m - exp_m) < 1e-4, f"Slope mismatch for {cand}: expected {exp_m:.6f}, got {act_m:.6f}"
        assert abs(act_c - exp_c) < 1e-4, f"Intercept mismatch for {cand}: expected {exp_c:.6f}, got {act_c:.6f}"
        assert abs(act_s - exp_s) < 1e-4, f"Score mismatch for {cand}: expected {exp_s:.6f}, got {act_s:.6f}"

    # Validate best run file
    with open(best_file, "r") as f:
        actual_best = f.read().strip()

    assert actual_best == best_run, f"{best_file} contains '{actual_best}', expected '{best_run}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
