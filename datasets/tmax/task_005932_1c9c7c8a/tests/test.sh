#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

import h5py
import numpy as np

BASE = "/home/user/ml_data_prep"
RUN_SH = os.path.join(BASE, "run.sh")
PARAMS = os.path.join(BASE, "params.csv")
FILTERED = os.path.join(BASE, "filtered.csv")
SPECTRA = os.path.join(BASE, "spectra.h5")


def original_params():
    random.seed(42)
    rows = []
    for _ in range(200):
        amp = round(random.uniform(1.0, 10.0), 2)
        seed = random.randint(1000, 9999)
        rows.append(f"{amp},{seed}\n")
    return "".join(rows)


def expected_signals(params_text):
    awk_program = r'''
BEGIN { FS="," }
{
    A = $1 + 0
    seed = $2 + 0
    srand(seed)
    area = 0
    for (i = 0; i < 100; i++) {
        x = i / 10
        y[i] = A * exp(-0.5 * (x - 5) * (x - 5)) + (rand() - 0.5) * 2
        area += y[i] * 0.1
    }
    analytical = A * 2.506628
    difference = area - analytical
    if (difference < 0) difference = -difference
    if (difference < 0.3) {
        for (i = 0; i < 100; i++) {
            if (i) printf ","
            printf "%.17g", y[i]
        }
        printf "\n"
    }
}
'''
    result = subprocess.run(
        ["gawk", awk_program],
        input=params_text,
        text=True,
        capture_output=True,
        check=True,
    )
    rows = [
        [float(value) for value in line.split(",")]
        for line in result.stdout.splitlines()
        if line.strip()
    ]
    return np.asarray(rows, dtype=np.float64)


def test_complete_pipeline():
    assert os.path.isfile(RUN_SH), f"Master script does not exist: {RUN_SH}"
    assert os.access(RUN_SH, os.X_OK), f"Master script is not executable: {RUN_SH}"

    expected_params = original_params()
    assert os.path.isfile(PARAMS), f"Input data does not exist: {PARAMS}"
    with open(PARAMS, "r") as f:
        actual_params = f.read()
    assert actual_params == expected_params, "params.csv was modified from the provided input"

    for output in (FILTERED, SPECTRA):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [RUN_SH],
        cwd=BASE,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"run.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    expected = expected_signals(expected_params)
    assert expected.ndim == 2 and expected.shape[1] == 100
    assert expected.shape[0] > 0

    assert os.path.isfile(FILTERED), f"Filtered CSV does not exist: {FILTERED}"
    with open(FILTERED, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "filtered.csv is empty, expected some valid signals."

    csv_rows = []
    for i, line in enumerate(lines):
        parts = line.strip().split(',')
        assert len(parts) == 100, f"Line {i+1} in filtered.csv does not have 100 values."
        try:
            row = [float(value) for value in parts]
        except ValueError as exc:
            raise AssertionError(f"Line {i+1} contains a non-numeric value: {exc}")
        assert np.all(np.isfinite(row)), f"Line {i+1} contains a non-finite value."
        csv_rows.append(row)

    csv_data = np.asarray(csv_rows, dtype=np.float64)
    assert csv_data.shape == expected.shape, (
        f"filtered.csv has shape {csv_data.shape}, expected {expected.shape}"
    )
    np.testing.assert_allclose(
        csv_data,
        expected,
        rtol=2e-5,
        atol=2e-6,
        err_msg="filtered.csv does not contain the correctly seeded, area-filtered signals",
    )

    assert os.path.isfile(SPECTRA), f"HDF5 file does not exist: {SPECTRA}"
    with h5py.File(SPECTRA, "r") as f:
        assert "signals" in f, "Dataset 'signals' not found."
        assert list(f.keys()) == ["signals"], "spectra.h5 must contain only the 'signals' dataset"
        dataset = f["signals"]
        assert isinstance(dataset, h5py.Dataset), "'signals' is not an HDF5 dataset"
        assert len(dataset.shape) == 2, f"Dataset should be 2D, got shape {dataset.shape}"
        assert dataset.shape[1] == 100, f"Expected 100 points per signal, got {dataset.shape[1]}"
        assert dataset.dtype == np.dtype(np.float64), f"Dataset is not float64, got {dataset.dtype}"
        data = dataset[:]

    assert data.shape == csv_data.shape, (
        f"HDF5 shape {data.shape} does not match filtered.csv shape {csv_data.shape}"
    )
    assert np.array_equal(data, csv_data), "HDF5 signals do not exactly contain the filtered.csv values"
    for i, row in enumerate(data):
        assert np.max(row) > 0.5, f"Signal max too low on row {i}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
