#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import sys

import netCDF4 as nc
import numpy as np
import pytest

SOURCE = "/home/user/prepare_data.c"
OUTPUT = "/home/user/output.nc"
LOG = "/home/user/result.log"
EXECUTABLE = "/tmp/prepare_data_verified"
INPUT = "/home/user/input.nc"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    """Compile the submitted C source and run it on fresh positive input data."""
    assert os.path.exists(SOURCE), f"Required C source {SOURCE} is missing."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE} must be a regular file."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE,
         "-o", EXECUTABLE, "-lnetcdf", "-lm"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        "prepare_data.c failed to compile:\n"
        + compile_result.stdout + "\n" + compile_result.stderr
    )
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

    # Confirm that the compiled program directly references the NetCDF C API
    # operations needed to read and create the requested datasets.
    nm_result = subprocess.run(
        ["nm", "-D", "--undefined-only", EXECUTABLE],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert nm_result.returncode == 0, f"Could not inspect executable symbols: {nm_result.stderr}"
    symbols = set(re.findall(r"\bnc_[A-Za-z0-9_]+", nm_result.stdout))
    required_exact = {"nc_open", "nc_create", "nc_def_dim", "nc_def_var", "nc_close"}
    missing = sorted(required_exact - symbols)
    assert not missing, f"Compiled program does not use required NetCDF C API calls: {missing}"
    assert any(s.startswith("nc_get_var") for s in symbols), \
        "Compiled program does not use a NetCDF variable-reading API."
    assert any(s.startswith("nc_put_var") for s in symbols), \
        "Compiled program does not use a NetCDF variable-writing API."

    with open(INPUT, "rb") as f:
        original_input = f.read()

    try:
        # Exercise the program rather than trusting artifacts left by the agent.
        # The values remain strictly positive and the required input schema is unchanged.
        challenge = (
            1.25
            + np.linspace(0.0, 4.0, 100) ** 1.35
            + 0.17 * np.sin(np.arange(100) * 0.73)
        ).astype(np.float64)
        with nc.Dataset(INPUT, "r+") as ds:
            assert "coarse_data" in ds.variables
            assert ds.variables["coarse_data"].shape == (100,)
            ds.variables["coarse_data"][:] = challenge

        for path in (OUTPUT, LOG):
            if os.path.lexists(path):
                os.unlink(path)

        run_result = subprocess.run(
            [EXECUTABLE],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert run_result.returncode == 0, (
            "Compiled prepare_data program failed:\n"
            + run_result.stdout + "\n" + run_result.stderr
        )
        yield
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)


def test_prepare_data_c_exists():
    assert os.path.exists(SOURCE), f"Required C source {SOURCE} is missing."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} is not a regular file."


def test_output_nc_exists():
    """Verify that the output NetCDF file was created."""
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    assert os.path.getsize(OUTPUT) > 0, f"{OUTPUT} is empty."


def test_result_log_exists():
    """Verify that the result.log file was created."""
    assert os.path.exists(LOG), f"Log file {LOG} is missing."
    assert os.path.isfile(LOG), f"{LOG} is not a file."


def test_data_and_calculations():
    """Verify mesh refinement, normalization, KL divergence, and NetCDF schema."""
    with nc.Dataset(INPUT, "r") as ds_in:
        coarse = np.asarray(ds_in.variables["coarse_data"][:], dtype=np.float64)

    expected_refined = np.zeros(199, dtype=np.float64)
    expected_refined[0::2] = coarse
    expected_refined[1::2] = (coarse[:-1] + coarse[1:]) / 2.0

    expected_P = expected_refined / np.sum(expected_refined)
    Q = 1.0 / 199.0
    expected_KL = np.sum(expected_P * np.log(expected_P / Q))

    with open(LOG, "r") as f:
        log_content = f.read().strip()
    expected_log = f"KL: {expected_KL:.6f}"
    assert log_content == expected_log, \
        f"Log content mismatch. Expected '{expected_log}', got '{log_content}'"

    with nc.Dataset(OUTPUT, "r") as ds_out:
        assert "n_refined" in ds_out.dimensions, \
            "Dimension 'n_refined' missing from output.nc"
        dim = ds_out.dimensions["n_refined"]
        assert len(dim) == 199, "Dimension 'n_refined' must have size 199"
        assert not dim.isunlimited(), "Dimension 'n_refined' must be a fixed-size dimension"

        assert "refined_data" in ds_out.variables, \
            "Variable 'refined_data' missing from output.nc"
        assert "P" in ds_out.variables, "Variable 'P' missing from output.nc"

        refined_var = ds_out.variables["refined_data"]
        p_var = ds_out.variables["P"]
        assert refined_var.dimensions == ("n_refined",), \
            "Variable 'refined_data' must depend on n_refined"
        assert p_var.dimensions == ("n_refined",), \
            "Variable 'P' must depend on n_refined"
        assert np.dtype(refined_var.dtype) == np.dtype("float64"), \
            "Variable 'refined_data' must be double precision"
        assert np.dtype(p_var.dtype) == np.dtype("float64"), \
            "Variable 'P' must be double precision"

        out_refined = np.asarray(refined_var[:])
        out_P = np.asarray(p_var[:])

    assert out_refined.shape == (199,)
    assert out_P.shape == (199,)
    assert np.allclose(out_refined, expected_refined, atol=1e-6), \
        "The 'refined_data' values do not match the expected interpolated values."
    assert np.allclose(out_P, expected_P, atol=1e-6), \
        "The 'P' values do not match the expected normalized distribution."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
