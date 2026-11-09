#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import nbformat
import numpy as np
import pandas as pd
import pytest
from scipy.signal import savgol_filter

NOTEBOOK_PATH = "/home/user/fit_spectrum.ipynb"
RESULTS_PATH = "/home/user/fit_results.json"
DATA_PATH = "/home/user/spectroscopy_data.csv"
EXPECTED_KEYS = {"c0", "c1", "c2", "peak_area"}


def execute_notebook():
    proc = subprocess.run(
        [
            "jupyter", "nbconvert", "--execute", "--to", "notebook", "--inplace",
            "--ExecutePreprocessor.timeout=120", NOTEBOOK_PATH,
        ],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert proc.returncode == 0, "Notebook execution failed:\n" + proc.stdout


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"Results JSON file not found at {RESULTS_PATH}"
    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {RESULTS_PATH} is not valid JSON.")

    missing_keys = EXPECTED_KEYS - set(results.keys())
    assert not missing_keys, f"JSON is missing required keys: {missing_keys}"
    for key in EXPECTED_KEYS:
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), (
            f"Value for {key} must be a number, got {type(results[key])}"
        )
        assert math.isfinite(results[key]), f"Value for {key} must be finite"
    return results


def analytical_result(csv_path):
    df = pd.read_csv(csv_path)
    selected = df[df["sensor_id"] == "A1"].sort_values("wavelength")
    wavelength = selected["wavelength"].to_numpy(dtype=float)
    intensity = selected["intensity"].to_numpy(dtype=float)
    smoothed = savgol_filter(intensity, window_length=5, polyorder=2)
    x_norm = wavelength - 4005.0
    outer = (wavelength < 4002.0) | (wavelength > 4008.0)
    X = np.column_stack((np.ones(outer.sum()), x_norm[outer], x_norm[outer] ** 2))
    beta = np.linalg.inv(X.T @ X) @ X.T @ smoothed[outer]
    baseline = beta[0] + beta[1] * x_norm + beta[2] * x_norm ** 2
    area = np.trapz(smoothed - baseline, wavelength)
    return {"c0": beta[0], "c1": beta[1], "c2": beta[2], "peak_area": area}


def assert_results_close(actual, expected, abs_tol=1e-6):
    for key, expected_val in expected.items():
        assert math.isclose(actual[key], float(expected_val), rel_tol=1e-7, abs_tol=abs_tol), (
            f"Value for {key} is incorrect. Expected ~{expected_val}, got {actual[key]}"
        )


def test_notebook_exists_and_contains_required_workflow():
    """Verify that a real, previously executed Jupyter notebook contains the mandated workflow."""
    assert os.path.isfile(NOTEBOOK_PATH), f"Jupyter Notebook not found at {NOTEBOOK_PATH}"
    try:
        notebook = nbformat.read(NOTEBOOK_PATH, as_version=4)
    except Exception as exc:
        pytest.fail(f"Notebook is not a valid Jupyter notebook: {exc}")

    assert notebook.cells, "Notebook has no cells"
    nonempty_code = [c for c in notebook.cells if c.cell_type == "code" and c.source.strip()]
    assert nonempty_code, "Notebook contains no executable code"
    assert all(c.get("execution_count") is not None for c in nonempty_code), (
        "Notebook must have been executed before verification"
    )

    source = "\n".join(c.source for c in nonempty_code)
    assert "spectroscopy_data.csv" in source, "Notebook does not read the required dataset"
    assert "savgol_filter" in source, "Notebook does not use scipy.signal.savgol_filter"
    assert re.search(r"(?:window_length\s*=\s*5|savgol_filter\s*\([^\n]*,\s*5\s*[,\)])", source), (
        "Savitzky-Golay window length 5 is not present"
    )
    assert re.search(r"(?:polyorder\s*=\s*2|savgol_filter\s*\([^\n]*,\s*5\s*,\s*2\s*[,\)])", source), (
        "Savitzky-Golay polynomial order 2 is not present"
    )
    assert re.search(r"(?:np|numpy)\.linalg\.inv\s*\(|\binv\s*\(", source), (
        "Notebook must explicitly use matrix inversion for OLS"
    )
    assert ".T" in source, "Notebook does not construct the transposed OLS matrix terms"
    assert "4005" in source, "Notebook does not apply the required wavelength normalization shift"
    assert "trapz" in source, "Notebook does not use the composite trapezoidal rule"

    assert notebook.cells[-1].cell_type == "code", "The final notebook cell must be a code cell"
    final_source = notebook.cells[-1].source
    assert "fit_results.json" in final_source, "The final cell does not write fit_results.json"
    assert re.search(r"json\.dump|\.write\s*\(|to_json", final_source), (
        "The final cell does not contain a JSON/file write operation"
    )


def test_results_json_exists_and_correct():
    """Execute the notebook freshly and retain the original exact-value assertions."""
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    execute_notebook()
    results = load_results()

    expected_values = {
        "c0": 10.021040856094269,
        "c1": 1.996160867768523,
        "c2": 0.5009088647008139,
        "peak_area": 62.43319086884611,
    }
    for key, expected_val in expected_values.items():
        actual_val = results[key]
        assert isinstance(actual_val, (int, float)), f"Value for {key} must be a number, got {type(actual_val)}"
        assert math.isclose(actual_val, expected_val, abs_tol=1e-4), (
            f"Value for {key} is incorrect. Expected ~{expected_val}, got {actual_val}"
        )


def test_notebook_computes_results_from_input_data():
    """Run the notebook on a hidden alternate dataset and compare with derived OLS results."""
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    rng = np.random.default_rng(7319)
    x = np.linspace(3999.5, 4010.5, 111)
    xn = x - 4005.0
    baseline = 17.3 - 1.27 * xn + 0.083 * xn ** 2
    signal = 31.0 * np.exp(-((x - 4005.15) ** 2) / (2 * 0.61 ** 2))
    noise = 0.37 * np.sin(73.0 * x) + 0.11 * np.cos(19.0 * x)
    a1 = pd.DataFrame({"sensor_id": "A1", "wavelength": x, "intensity": baseline + signal + noise})
    b2 = pd.DataFrame({
        "sensor_id": "B2",
        "wavelength": x,
        "intensity": baseline + 4.0 * signal - 2.0 * noise + 25.0,
    })
    alternate = pd.concat([a1, b2], ignore_index=True).iloc[rng.permutation(222)]

    try:
        alternate.to_csv(DATA_PATH, index=False)
        expected = analytical_result(DATA_PATH)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        execute_notebook()
        actual = load_results()
        assert_results_close(actual, expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if os.path.isfile(NOTEBOOK_PATH):
            execute_notebook()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
