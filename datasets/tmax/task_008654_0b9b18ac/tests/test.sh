#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pytest
import numpy as np
import pandas as pd
from scipy.optimize import least_squares


def test_training_features_exists_and_format():
    """Check if training_features.csv exists and has the correct format."""
    file_path = "/home/user/training_features.csv"
    assert os.path.isfile(file_path), f"Missing output file: {file_path}"

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["StrainID", "r", "K"], f"Incorrect header in {file_path}. Expected ['StrainID', 'r', 'K'], got {header}"

        rows = list(reader)
        assert len(rows) == 3, f"Expected 3 rows of data, got {len(rows)}"

        strains = [row[0] for row in rows]
        assert strains == ["Strain_Alpha", "Strain_Beta", "Strain_Gamma"], f"Strains are not sorted alphabetically or missing: {strains}"


def fitted_parameters_from_observations():
    """Fit the specified logistic model using each strain's observed Time=0 value."""
    data = pd.read_csv("/home/user/growth_data.csv")
    expected = {}

    for strain, group in data.groupby("StrainID"):
        group = group.sort_values("Time")
        times = group["Time"].to_numpy(dtype=float)
        observed = group["OD600"].to_numpy(dtype=float)
        initial_rows = group.loc[np.isclose(group["Time"].to_numpy(dtype=float), 0.0), "OD600"]
        assert len(initial_rows) == 1, f"Expected exactly one Time=0 observation for {strain}"
        y0 = float(initial_rows.iloc[0])

        def residuals(params):
            r, k = params
            prediction = k / (1.0 + (k / y0 - 1.0) * np.exp(-r * times))
            return prediction - observed

        result = least_squares(
            residuals,
            x0=np.array([0.5, max(0.5, float(observed.max()))]),
            bounds=([0.01, 0.1], [5.0, 5.0]),
            xtol=1e-13,
            ftol=1e-13,
            gtol=1e-13,
            max_nfev=10000,
        )
        assert result.success, f"Reference fit failed for {strain}: {result.message}"
        expected[strain] = {"r": float(result.x[0]), "K": float(result.x[1])}

    return expected


def test_training_features_values():
    """Check fitted parameters against the model with observed Time=0 initial conditions."""
    file_path = "/home/user/training_features.csv"
    assert os.path.isfile(file_path), f"Missing output file: {file_path}"
    expected = fitted_parameters_from_observations()

    with open(file_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            strain = row["StrainID"]
            assert strain in expected, f"Unexpected StrainID: {strain}"

            try:
                r_val = float(row["r"])
                k_val = float(row["K"])
            except ValueError:
                pytest.fail(f"Non-numeric values found for {strain}: r={row['r']}, K={row['K']}")

            expected_r = expected[strain]["r"]
            expected_k = expected[strain]["K"]

            # Preserve the original 5% tolerance, but compare against a fit that
            # uses the experimentally observed initial condition as instructed.
            r_tol = expected_r * 0.05
            k_tol = expected_k * 0.05

            assert math.isclose(r_val, expected_r, abs_tol=r_tol), f"r value for {strain} is {r_val}, expected ~{expected_r}"
            assert math.isclose(k_val, expected_k, abs_tol=k_tol), f"K value for {strain} is {k_val}, expected ~{expected_k}"


def test_growth_fits_png_exists():
    """Check if growth_fits.png exists and is a non-empty file."""
    file_path = "/home/user/growth_fits.png"
    assert os.path.isfile(file_path), f"Missing image file: {file_path}"
    assert os.path.getsize(file_path) > 0, f"Image file {file_path} is empty"

    with open(file_path, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"File {file_path} is not a valid PNG image"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
