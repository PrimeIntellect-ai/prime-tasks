#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import math
import os
import subprocess
import sys
import tempfile

import h5py
import netCDF4 as nc
import numpy as np
import pytest

PROJECT = "/home/user/project"
FIT_PATH = os.path.join(PROJECT, "fit.py")
DATA_H5 = os.path.join(PROJECT, "data.h5")
OUTPUT_NC = os.path.join(PROJECT, "output.nc")


def load_fit():
    assert os.path.isfile(FIT_PATH), f"Implementation file {FIT_PATH} is missing."
    sys.path.insert(0, PROJECT)
    try:
        sys.modules.pop("fit", None)
        return importlib.import_module("fit")
    finally:
        sys.path.pop(0)


def test_pytest_passes():
    """Keep the original regression-suite assertion."""
    test_file = os.path.join(PROJECT, "test_fit.py")
    assert os.path.isfile(test_file), f"Test file {test_file} is missing."

    result = subprocess.run(
        ["python3", "-m", "pytest", test_file],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pytest failed on {test_file}. Output:\n{result.stdout}\n{result.stderr}"
    )


def test_compute_metric_is_stable_correct_and_still_shuffles():
    """Independently exercise compute_metric instead of trusting editable tests."""
    fit = load_fit()
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    test_array = rng.normal(size=1024)
    fft_vals = np.abs(np.fft.rfft(test_array))
    expected = math.fsum(
        float(value) * (1 if i % 2 == 0 else -1)
        for i, value in enumerate(fft_vals)
    )

    calls = []

    def identity_shuffle(indices):
        calls.append(list(indices))

    fit.random.shuffle = identity_shuffle
    identity_result = fit.compute_metric(test_array)

    def reverse_shuffle(indices):
        calls.append(list(indices))
        indices.reverse()

    fit.random.shuffle = reverse_shuffle
    reverse_result = fit.compute_metric(test_array)

    def rotated_shuffle(indices):
        calls.append(list(indices))
        cut = len(indices) // 3
        indices[:] = indices[cut:] + indices[:cut]

    fit.random.shuffle = rotated_shuffle
    rotated_result = fit.compute_metric(test_array)

    expected_indices = list(range(len(fft_vals)))
    assert calls == [expected_indices, expected_indices, expected_indices], (
        "compute_metric must still pass all FFT indices to random.shuffle"
    )
    assert identity_result == expected
    assert reverse_result == expected
    assert rotated_result == expected


def assert_netcdf_matches(path, expected):
    with nc.Dataset(path, "r") as ds:
        assert "power_spectrum" in ds.variables, (
            "Variable 'power_spectrum' not found"
        )
        var = ds.variables["power_spectrum"]

        # Preserve the original shape, dtype, and dimension-name checks.
        assert list(var.shape) == list(expected.shape), (
            f"Expected shape {list(expected.shape)}, got {list(var.shape)}"
        )
        assert str(var.dtype) in ["float64", "f8", ">f8", "<f8"], (
            f"Expected float64/f8 dtype, got {var.dtype}"
        )
        dims = list(ds.dimensions.keys())
        assert "row" in dims, "Dimension 'row' missing in netCDF file."
        assert "freq" in dims, "Dimension 'freq' missing in netCDF file."
        assert tuple(var.dimensions) == ("row", "freq")

        actual = np.asarray(var[:])
        assert np.array_equal(actual, expected), (
            "power_spectrum values do not equal abs(rfft(spectra))"
        )


def test_output_nc_exists_and_correct():
    """Validate the required workspace artifact against data.h5."""
    assert os.path.isfile(OUTPUT_NC), (
        f"Output file {OUTPUT_NC} is missing. Did you run save_to_netcdf?"
    )
    with h5py.File(DATA_H5, "r") as source:
        assert "spectra" in source
        spectra = source["spectra"][:]
    expected = np.abs(np.fft.rfft(spectra, axis=1)).astype(np.float64)
    assert expected.shape == (10, 513)
    assert_netcdf_matches(OUTPUT_NC, expected)


def test_save_to_netcdf_on_fresh_unseen_input():
    """Execute save_to_netcdf and derive the expected values independently."""
    fit = load_fit()
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    spectra = rng.normal(size=(7, 31)).astype(np.float64)
    expected = np.abs(np.fft.rfft(spectra, axis=1)).astype(np.float64)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_h5 = os.path.join(tmpdir, "fresh_input.h5")
        output_nc = os.path.join(tmpdir, "fresh_output.nc")
        with h5py.File(input_h5, "w") as source:
            source.create_dataset("spectra", data=spectra)

        fit.save_to_netcdf(input_h5, output_nc)
        assert os.path.isfile(output_nc), "save_to_netcdf did not create its output"
        assert_netcdf_matches(output_nc, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
