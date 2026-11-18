#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import numpy as np

SOURCE = "/home/user/fit_model.c"
BINARY = "/tmp/fit_model_submission"
DATA = "/home/user/data.csv"
ANALYTICAL = "/home/user/analytical_results.txt"
MCMC = "/home/user/mcmc_results.txt"


def read_results(path):
    with open(path, 'r') as f:
        content = f.read().strip()
        if not content:
            return []
        return [float(x) for x in content.split(',')]


def remove_outputs():
    for path in (ANALYTICAL, MCMC):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_submission():
    remove_outputs()
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=180)
    assert os.path.isfile(ANALYTICAL), f"Program did not create {ANALYTICAL}."
    assert os.path.isfile(MCMC), f"Program did not create {MCMC}."


def test_fit_model_c_exists():
    """Check if the C program source file exists."""
    assert os.path.isfile(SOURCE), "C program /home/user/fit_model.c is missing."


def test_compile_and_exercise_on_derived_data():
    """Compile the submitted C source and exercise it on independently derived data."""
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY, "-lm"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable."

    with open(DATA, "rb") as f:
        original_data = f.read()

    rows = []
    for i in range(100):
        x1 = (((i * 37) % 101) - 50) / 9.0
        x2 = (((i * 61 + 13) % 103) - 51) / 11.0 + 0.17 * math.sin(i)
        noise = 0.22 * math.sin(0.73 * i) - 0.11 * math.cos(1.31 * i)
        y = -1.75 + 0.63 * x1 + 1.42 * x2 + noise
        rows.append((x1, x2, y))

    X = np.array([[1.0, x1, x2] for x1, x2, _ in rows], dtype=float)
    y = np.array([value for _, _, value in rows], dtype=float)
    expected = np.linalg.solve(X.T @ X, X.T @ y)

    try:
        with open(DATA, "w") as f:
            f.write("x1,x2,y\n")
            for x1, x2, value in rows:
                f.write(f"{x1:.8f},{x2:.8f},{value:.8f}\n")

        run_submission()
        analytical = read_results(ANALYTICAL)
        mcmc = read_results(MCMC)

        assert len(analytical) == 3, "Derived-data analytical output must contain exactly 3 values."
        assert len(mcmc) == 3, "Derived-data MCMC output must contain exactly 3 values."
        assert all(math.isfinite(v) for v in analytical + mcmc), "Results must be finite numbers."

        for value, target in zip(analytical, expected):
            assert abs(value - target) <= 0.015, (
                f"Analytical result {value} does not match the OLS value {target} "
                "for the verifier-generated dataset."
            )
        for sampled, exact in zip(mcmc, analytical):
            assert abs(sampled - exact) <= 0.05, (
                f"MCMC result {sampled} is not close to analytical result {exact} "
                "for the verifier-generated dataset."
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        # Produce fresh outputs from the required reference dataset for the
        # original result assertions below.
        run_submission()


def test_analytical_results():
    """Check if analytical results are correct and match the expected OLS solution."""
    path = "/home/user/analytical_results.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    try:
        vals = read_results(path)
    except ValueError:
        assert False, f"Could not parse floats from {path}. Ensure it is comma-separated."

    assert len(vals) == 3, f"Expected 3 values in {path}, got {len(vals)}."

    expected = [2.441, 1.189, -0.765]
    for v, e in zip(vals, expected):
        assert abs(v - e) <= 0.015, f"Analytical result {v} differs from expected {e} by more than allowed tolerance."


def test_mcmc_results():
    """Check if MCMC results exist and have converged close to the analytical solution."""
    path_mcmc = "/home/user/mcmc_results.txt"
    path_anal = "/home/user/analytical_results.txt"

    assert os.path.isfile(path_mcmc), f"File {path_mcmc} is missing."
    if not os.path.isfile(path_anal):
        return  # Handled by previous test

    try:
        mcmc_vals = read_results(path_mcmc)
        anal_vals = read_results(path_anal)
    except ValueError:
        assert False, "Could not parse floats from results files."

    assert len(mcmc_vals) == 3, f"Expected 3 values in {path_mcmc}, got {len(mcmc_vals)}."

    for m, a in zip(mcmc_vals, anal_vals):
        assert abs(m - a) <= 0.05, f"MCMC result {m} differs from analytical {a} by more than 0.05. MCMC did not converge sufficiently."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
