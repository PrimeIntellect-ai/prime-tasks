#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import solve_ivp

ROOT = "/home/user/ml_data"
GENERATE = os.path.join(ROOT, "generate.py")
DATASET = os.path.join(ROOT, "dataset.csv")
CALC_STATS = os.path.join(ROOT, "stats_tool", "calc_stats")
REPORT = os.path.join(ROOT, "stability_report.txt")


@pytest.fixture(scope="session", autouse=True)
def run_generator():
    assert os.path.isfile(GENERATE), f"File missing: {GENERATE}"
    if os.path.exists(DATASET):
        os.remove(DATASET)
    subprocess.run(
        ["python3", GENERATE],
        cwd=ROOT,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(DATASET), "generate.py did not create dataset.csv"


def test_generate_py_updated():
    assert os.path.isfile(GENERATE), f"File missing: {GENERATE}"
    with open(GENERATE, "r") as f:
        content = f.read()
    assert "solve_ivp" in content, "generate.py does not use scipy.integrate.solve_ivp"
    assert "BDF" in content or "Radau" in content or "LSODA" in content, \
        "generate.py does not seem to specify a stiff solver method like BDF or Radau"


def test_calc_stats_compiled():
    assert os.path.isfile(CALC_STATS), f"Executable missing: {CALC_STATS}"
    assert os.access(CALC_STATS, os.X_OK), f"File is not executable: {CALC_STATS}"
    with open(CALC_STATS, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc_stats is not a compiled ELF executable"

    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
        sample = f.name
        f.write("y1,y2\n-3.125,100\n7.25,-4\n-6.5,999\n")
    try:
        result = subprocess.run(
            [CALC_STATS, sample], check=True, timeout=10,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.stdout.strip() == "7.2500", \
            "calc_stats did not compute the maximum absolute value of the first column"
    finally:
        os.unlink(sample)


def _reference_solutions(t_eval):
    def deriv(t, y):
        return [y[1], 50.0 * (1.0 - y[0] ** 2) * y[1] - y[0]]

    references = []
    for method in ("BDF", "Radau", "LSODA"):
        sol = solve_ivp(deriv, (0.0, 100.0), [2.0, 0.0], method=method, t_eval=t_eval)
        assert sol.success
        references.append(sol.y.T)
    for method in ("BDF", "Radau"):
        sol = solve_ivp(
            deriv, (0.0, 100.0), [2.0, 0.0], method=method, t_eval=t_eval,
            rtol=1e-7, atol=1e-9
        )
        assert sol.success
        references.append(sol.y.T)
    return references


def test_dataset_csv_valid():
    assert os.path.isfile(DATASET), f"File missing: {DATASET}"

    with open(DATASET, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "dataset.csv is empty"
        assert header == ["y1", "y2"], f"Unexpected CSV header: {header}"
        rows = list(reader)

    assert len(rows) == 1000, f"dataset.csv must contain exactly 1000 data rows, got {len(rows)}"
    assert all(len(row) == 2 for row in rows), "Every dataset row must have exactly two columns"

    for row_idx, row in enumerate(rows, start=2):
        for col_idx, val in enumerate(row):
            val_upper = val.strip().upper()
            assert "NAN" not in val_upper and "INF" not in val_upper, \
                f"dataset.csv contains invalid value '{val}' at row {row_idx}, col {col_idx}"

    frame = pd.read_csv(DATASET)
    assert list(frame.columns) == ["y1", "y2"]
    assert frame.shape == (1000, 2)
    try:
        values = frame.to_numpy(dtype=float)
    except (TypeError, ValueError) as exc:
        pytest.fail(f"dataset.csv contains non-numeric data: {exc}")
    assert np.isfinite(values).all(), "dataset.csv contains NaN or infinite values"
    np.testing.assert_allclose(values[0], [2.0, 0.0], rtol=0.0, atol=1e-12)

    t_eval = np.linspace(0.0, 100.0, 1000)
    references = _reference_solutions(t_eval)
    errors = []
    for ref in references:
        delta = np.abs(values - ref)
        errors.append((
            float(np.sqrt(np.mean(delta[:, 0] ** 2))),
            float(np.sqrt(np.mean(delta[:, 1] ** 2))),
            float(np.max(delta[:, 0])),
            float(np.max(delta[:, 1])),
        ))
    best = min(errors, key=lambda e: e[0] + e[1] / 50.0)
    assert best[0] < 0.03 and best[1] < 1.0 and best[2] < 0.4 and best[3] < 20.0, \
        f"dataset values do not match a solve_ivp Van der Pol solution at the required times; errors={best}"


def test_stability_report():
    assert os.path.isfile(REPORT), f"File missing: {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read().strip()

    assert content != "NaN_or_Inf", \
        "stability_report.txt indicates NaNs or Infs were found by the stats tool"
    try:
        max_val = float(content)
    except ValueError:
        pytest.fail(f"stability_report.txt does not contain a valid float: '{content}'")
    assert 2.0 <= max_val <= 2.05, \
        f"Maximum amplitude {max_val} in stability_report.txt is not within the expected range [2.0, 2.05] for the stable limit cycle"

    actual = subprocess.run(
        [CALC_STATS, DATASET], check=True, timeout=10,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout.strip()
    assert content == actual, \
        "stability_report.txt is not the output of calc_stats on the generated dataset.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
