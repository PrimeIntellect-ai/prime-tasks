#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import stat
import subprocess

import numpy as np
import pytest

CPP_PATH = "/home/user/generate_data.cpp"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
CSV_PATH = "/home/user/training_data.csv"
FIXED_6 = re.compile(r"^[+-]?\d+\.\d{6}$")


def reference_solution():
    """Recompute the requested finite-difference solution from the equation."""
    h = 0.01
    u = np.zeros(101, dtype=float)

    for _ in range(100):
        interior = u[1:100]
        residual = (-(u[2:101] - 2.0 * interior + u[0:99]) / (h * h)
                    + np.exp(interior) - 10.0)

        jacobian = np.diag(2.0 / (h * h) + np.exp(interior))
        off_diag = np.full(98, -1.0 / (h * h))
        jacobian += np.diag(off_diag, 1) + np.diag(off_diag, -1)

        update = np.linalg.solve(jacobian, -residual)
        u[1:100] += update
        if np.max(np.abs(update)) < 1e-7:
            return u

    pytest.fail("Reference Newton solve did not converge")


def validate_csv(csv_path):
    with open(csv_path, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "CSV is empty."
    assert rows[0] == ["x", "u"], f"CSV header is incorrect, got {rows[0]}"

    data_rows = rows[1:]
    assert len(data_rows) == 101, \
        f"CSV must have exactly 101 data rows, got {len(data_rows)}"

    x_vals = []
    u_vals = []
    for i, row in enumerate(data_rows):
        assert len(row) == 2, f"Row {i + 1} does not have exactly 2 columns."
        assert FIXED_6.fullmatch(row[0]), \
            f"x value {row[0]!r} is not formatted to exactly 6 decimal places."
        assert FIXED_6.fullmatch(row[1]), \
            f"u value {row[1]!r} is not formatted to exactly 6 decimal places."
        try:
            x_val = float(row[0])
            u_val = float(row[1])
        except ValueError:
            pytest.fail(f"Could not parse row {i + 1} as floats: {row}")
        assert math.isfinite(x_val) and math.isfinite(u_val), \
            f"Row {i + 1} contains a non-finite value."
        x_vals.append(x_val)
        u_vals.append(u_val)

    for i, x_val in enumerate(x_vals):
        assert math.isclose(x_val, i * 0.01, rel_tol=0.0, abs_tol=5e-7), \
            f"x[{i}] must be {i * 0.01:.6f}, got {x_val}"

    assert math.isclose(x_vals[0], 0.0, abs_tol=1e-5), \
        f"x[0] != 0.0, got {x_vals[0]}"
    assert math.isclose(u_vals[0], 0.0, abs_tol=1e-5), \
        f"u[0] != 0.0, got {u_vals[0]}"
    assert math.isclose(x_vals[-1], 1.0, abs_tol=1e-5), \
        f"x[-1] != 1.0, got {x_vals[-1]}"
    assert math.isclose(u_vals[-1], 0.0, abs_tol=1e-5), \
        f"u[-1] != 0.0, got {u_vals[-1]}"

    u_mid = u_vals[50]
    assert 1.08 < u_mid < 1.09, \
        f"Midpoint value u(0.5)={u_mid} is out of expected range [1.08, 1.09]"

    expected = reference_solution()
    for i, (actual, wanted) in enumerate(zip(u_vals, expected)):
        assert math.isclose(actual, float(wanted), rel_tol=0.0, abs_tol=5.1e-7), \
            f"u[{i}]={actual} does not match the recomputed solution {wanted:.9f}"

    # Four independent rounding errors in the second-difference numerator can
    # contribute up to about 0.02 after division by h^2. This tolerance checks
    # the equation at the precision the required six-decimal CSV retains.
    h = 0.01
    for i in range(1, 100):
        second_deriv = (u_vals[i + 1] - 2 * u_vals[i] + u_vals[i - 1]) / (h ** 2)
        residual = -second_deriv + math.exp(u_vals[i]) - 10
        assert abs(residual) < 0.021, \
            f"Discrete residual at index {i} (x={x_vals[i]}) is too large: {residual}"


def test_files_exist():
    assert os.path.isfile(CPP_PATH), "generate_data.cpp is missing."
    assert os.path.isfile(SCRIPT_PATH), "run_pipeline.sh is missing."
    assert os.path.isfile(CSV_PATH), "training_data.csv is missing."


def test_script_executable():
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), "run_pipeline.sh is not executable."


def test_cpp_and_pipeline_generate_data():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script = f.read()
    assert "g++" in script, "run_pipeline.sh must invoke g++."
    assert "-O3" in script, "run_pipeline.sh must compile using -O3."
    assert "generate_data.cpp" in script, \
        "run_pipeline.sh must compile generate_data.cpp."

    compiled = "/tmp/submission_generator"
    subprocess.run(
        ["g++", "-O3", CPP_PATH, "-o", compiled],
        check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    subprocess.run(
        [compiled], check=True, timeout=30, cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert os.path.isfile(CSV_PATH), \
        "The compiled C++ program did not generate training_data.csv."
    validate_csv(CSV_PATH)

    os.remove(CSV_PATH)
    subprocess.run(
        [SCRIPT_PATH], check=True, timeout=90, cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert os.path.isfile(CSV_PATH), \
        "run_pipeline.sh did not regenerate training_data.csv."


def test_csv_contents():
    validate_csv(CSV_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
