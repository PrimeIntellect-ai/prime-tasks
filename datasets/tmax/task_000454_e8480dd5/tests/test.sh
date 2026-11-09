#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the required notebook itself can regenerate the output from scratch.
rm -f /home/user/band_features.csv
notebook_ok=1
if ! jupyter nbconvert --to notebook --execute --inplace \
    --ExecutePreprocessor.timeout=180 \
    /home/user/process_spectra.ipynb >/tmp/nbconvert.log 2>&1; then
    notebook_ok=0
    cat /tmp/nbconvert.log
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
import pytest

def gradient(y, dx):
    n = len(y)
    grad = [0.0] * n
    if n > 1:
        grad[0] = (y[1] - y[0]) / dx
        grad[-1] = (y[-1] - y[-2]) / dx
        for i in range(1, n - 1):
            grad[i] = (y[i+1] - y[i-1]) / (2.0 * dx)
    return grad

def trapz(y, dx):
    n = len(y)
    if n == 0:
        return 0.0
    if n == 1:
        return 0.0
    return (y[0] / 2.0 + sum(y[1:-1]) + y[-1] / 2.0) * dx

@pytest.fixture
def expected_features():
    raw_csv = "/home/user/raw_spectra.csv"
    assert os.path.exists(raw_csv), f"Missing raw data file: {raw_csv}"

    expected = {}
    with open(raw_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        wv_cols = [c for c in reader.fieldnames if c.startswith("wv_")]
        wavelengths = [int(c.split("_")[1]) for c in wv_cols]

        for row in reader:
            obs_id = row["obs_id"]
            signal = [float(row[c]) for c in wv_cols]

            deriv = gradient(signal, 10.0)
            abs_deriv = [abs(d) for d in deriv]

            b1_vals = [abs_deriv[i] for i, w in enumerate(wavelengths) if 400 <= w <= 490]
            b2_vals = [abs_deriv[i] for i, w in enumerate(wavelengths) if 500 <= w <= 590]
            b3_vals = [abs_deriv[i] for i, w in enumerate(wavelengths) if 600 <= w <= 690]
            b4_vals = [abs_deriv[i] for i, w in enumerate(wavelengths) if 700 <= w <= 800]

            expected[obs_id] = {
                "band_1": trapz(b1_vals, 10.0),
                "band_2": trapz(b2_vals, 10.0),
                "band_3": trapz(b3_vals, 10.0),
                "band_4": trapz(b4_vals, 10.0),
            }
    return expected

def test_notebook_exists():
    """Test that the Jupyter Notebook was created and is a valid notebook with code."""
    nb_path = "/home/user/process_spectra.ipynb"
    assert os.path.exists(nb_path), f"Notebook missing at {nb_path}"
    assert os.path.isfile(nb_path), f"Path {nb_path} is not a file."

    with open(nb_path, "r", encoding="utf-8") as f:
        notebook = json.load(f)
    assert notebook.get("nbformat") == 4, "Notebook must use Jupyter nbformat 4."
    cells = notebook.get("cells")
    assert isinstance(cells, list), "Notebook has no valid cells list."
    assert any(
        cell.get("cell_type") == "code" and "".join(cell.get("source", [])).strip()
        for cell in cells
    ), "Notebook must contain at least one non-empty code cell."

def test_band_features_output(expected_features):
    """Test that the band_features.csv output is correct."""
    out_path = "/home/user/band_features.csv"
    assert os.path.exists(out_path), f"Output file missing at {out_path}"

    with open(out_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual_cols = reader.fieldnames
        expected_cols = ["obs_id", "band_1", "band_2", "band_3", "band_4"]

        assert actual_cols == expected_cols, f"Columns mismatch. Expected {expected_cols}, got {actual_cols}"

        actual_data = list(reader)

    assert len(actual_data) == len(expected_features), f"Expected {len(expected_features)} rows, got {len(actual_data)}"

    actual_ids = [row["obs_id"] for row in actual_data]
    assert len(actual_ids) == len(set(actual_ids)), "Output contains duplicate obs_id values."
    assert set(actual_ids) == set(expected_features), \
        f"Observation IDs mismatch. Missing: {set(expected_features) - set(actual_ids)}; unexpected: {set(actual_ids) - set(expected_features)}"

    for row in actual_data:
        obs_id = row["obs_id"]
        assert obs_id in expected_features, f"Unexpected obs_id found: {obs_id}"

        for band in ["band_1", "band_2", "band_3", "band_4"]:
            expected_val = expected_features[obs_id][band]
            try:
                actual_val = float(row[band])
            except ValueError:
                pytest.fail(f"Non-numeric value for {band} in obs_id {obs_id}: {row[band]}")

            assert math.isclose(actual_val, expected_val, rel_tol=1e-3, abs_tol=1e-3), \
                f"Value mismatch for {obs_id} {band}. Expected ~{expected_val:.4f}, got {actual_val:.4f}"
TEST_EOF

if [ "$notebook_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
