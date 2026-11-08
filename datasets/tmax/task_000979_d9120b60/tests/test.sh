#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import re
import struct
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import odeint
from scipy.optimize import curve_fit

VENV_PYTHON = "/home/user/env/bin/python"
SCRIPT_PATH = "/home/user/augment.py"
CSV_PATH = "/home/user/output/augmented_I.csv"
PLOT_PATH = "/home/user/output/trajectories.png"
DATA_PATH = "/home/user/data/experimental.csv"


def sir_model(y, t, beta, gamma):
    S, I, R = y
    N = 1000.0
    return [-beta * S * I / N,
            beta * S * I / N - gamma * I,
            gamma * I]


def assert_original_data_unchanged():
    actual = pd.read_csv(DATA_PATH)
    assert list(actual.columns) == ["t", "S", "I", "R"]
    assert actual.shape == (51, 4)

    t = np.linspace(0, 50, 51)
    solution = odeint(sir_model, [990, 10, 0], t, args=(0.4, 0.1))
    rng = np.random.RandomState(100)
    noisy_i = np.clip(solution[:, 1] + rng.normal(0, 15, len(t)), 0, None)

    assert np.allclose(actual["t"].to_numpy(), t, rtol=0, atol=1e-10)
    assert np.allclose(actual["S"].to_numpy(), solution[:, 0], rtol=1e-8, atol=1e-6)
    assert np.allclose(actual["I"].to_numpy(), noisy_i, rtol=1e-8, atol=1e-6)
    assert np.allclose(actual["R"].to_numpy(), solution[:, 2], rtol=1e-8, atol=1e-6)


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment Python executable missing at {VENV_PYTHON}"
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert_original_data_unchanged()

    subprocess.run(
        [VENV_PYTHON, "-c", "import numpy, scipy, pandas, matplotlib"],
        check=True,
        timeout=60,
    )

    for path in (CSV_PATH, PLOT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [VENV_PYTHON, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"augment.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_venv_exists():
    """Verify that the virtual environment was created and contains a Python executable."""
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment Python executable missing at {VENV_PYTHON}"


def test_script_exists():
    """Verify that the student's script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_script_uses_required_operations():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    calls = []
    seed_42 = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            name = node.func.attr
        elif isinstance(node.func, ast.Name):
            name = node.func.id
        else:
            continue
        calls.append(name)
        if name == "seed" and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and arg.value == 42:
                seed_42 = True

    assert "curve_fit" in calls, "augment.py must use scipy.optimize.curve_fit"
    assert seed_42, "augment.py must call numpy.random.seed(42)"
    assert "multivariate_normal" in calls, "augment.py must use numpy.random.multivariate_normal"
    assert "scatter" in calls, "The original noisy infected data must be plotted as scatter points"
    assert "plot" in calls, "The simulated trajectories must be plotted as lines"
    assert "savefig" in calls, "The plot must be saved with savefig"


def test_output_plot_exists():
    """Verify that the trajectories plot was generated."""
    assert os.path.isfile(PLOT_PATH), f"Plot missing at {PLOT_PATH}"


def test_output_plot_is_valid_png():
    assert os.path.getsize(PLOT_PATH) > 1000, "Plot is empty or only a placeholder"
    with open(PLOT_PATH, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "trajectories.png is not a PNG file"
    assert header[12:16] == b"IHDR", "PNG is missing its IHDR chunk"
    width, height = struct.unpack(">II", header[16:24])
    assert width >= 100 and height >= 100, "Plot dimensions are unexpectedly small"


def test_augmented_csv_exists():
    """Verify that the augmented CSV file exists."""
    assert os.path.isfile(CSV_PATH), f"Augmented CSV missing at {CSV_PATH}"


def test_augmented_csv_content():
    """Verify the structure and basic correctness of the augmented CSV."""
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "The augmented CSV file is empty."
    expected_header = ["t", "I_0", "I_1", "I_2", "I_3", "I_4"]
    assert rows[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {rows[0]}"

    data_rows = rows[1:]
    assert len(data_rows) == 51, f"Expected exactly 51 data rows for t in [0, 50], got {len(data_rows)}"
    decimal_number = re.compile(r"^-?\d+(?:\.(\d+))?$")

    for i, row in enumerate(data_rows):
        assert len(row) == 6, f"Row {i+1} has {len(row)} columns, expected 6."
        try:
            t_val = float(row[0])
            i_vals = [float(v) for v in row[1:]]
        except ValueError as exc:
            pytest.fail(f"Could not parse numeric values in row {i+1}: {exc}")

        assert math.isclose(t_val, i, abs_tol=1e-5), f"Time point at row {i+1} is {t_val}, expected {i}."
        assert all(math.isfinite(v) for v in i_vals), f"Row {i+1} contains a non-finite infected value"

        for text in row[1:]:
            match = decimal_number.fullmatch(text.strip())
            assert match, f"Infected value {text!r} is not an ordinary rounded decimal"
            assert match.group(1) is None or len(match.group(1)) <= 4, f"Value {text!r} was not rounded to 4 decimal places"

        if i == 0:
            for j, i_val in enumerate(i_vals):
                assert math.isclose(i_val, 10.0, abs_tol=0.1), f"Initial condition I_{j} at t=0 should be 10.0, got {i_val}"


def test_augmented_values_match_required_fit_and_seeded_sampling():
    experimental = pd.read_csv(DATA_PATH)
    fit_t = experimental["t"].to_numpy(dtype=float)
    observed_i = experimental["I"].to_numpy(dtype=float)

    def infected_curve(t, beta, gamma):
        return odeint(sir_model, [990, 10, 0], t, args=(beta, gamma))[:, 1]

    fitted, covariance = curve_fit(
        infected_curve,
        fit_t,
        observed_i,
        p0=[0.5, 0.2],
        bounds=([0.001, 0.001], [1.0, 1.0]),
    )
    rng = np.random.RandomState(42)
    samples = rng.multivariate_normal(fitted, covariance, size=5)
    output_t = np.linspace(0, 50, 51)
    expected = np.column_stack([
        odeint(sir_model, [990, 10, 0], output_t, args=tuple(sample))[:, 1]
        for sample in samples
    ])

    actual = pd.read_csv(CSV_PATH)
    assert list(actual.columns) == ["t", "I_0", "I_1", "I_2", "I_3", "I_4"]
    actual_values = actual.iloc[:, 1:].to_numpy(dtype=float)
    assert actual_values.shape == expected.shape
    assert np.all(np.isfinite(actual_values)), "CSV contains non-finite trajectory values"
    assert np.allclose(actual_values, expected, rtol=0.01, atol=0.5), (
        "The trajectories do not match the curve_fit covariance, seed-42 multivariate samples, "
        "and resulting SIR simulations"
    )
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
