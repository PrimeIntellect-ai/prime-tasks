#!/bin/bash
set -e
mkdir -p /logs/verifier
cp /home/user/climate_grid.nc /tmp/climate_grid.original.nc

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import netCDF4 as nc
import numpy as np

HOME = "/home/user"
SOURCE = os.path.join(HOME, "impute.go")
RESULT = os.path.join(HOME, "result.txt")
BINARY = "/tmp/impute_submission"


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file {path} is missing."
    assert os.path.isfile(path), f"Path {path} exists but is not a regular file."


def read_result():
    assert_regular_file(RESULT)
    with open(RESULT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", content), (
        f"Result must contain one floating-point value with exactly four decimal places; got {content!r}."
    )
    return content


def run_submission():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    proc = subprocess.run(
        [BINARY], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=120
    )
    assert proc.returncode == 0, (
        f"Compiled imputation program failed with status {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return read_result()


def write_grid(data):
    path = os.path.join(HOME, "climate_grid.nc")
    if os.path.exists(path):
        os.remove(path)
    ds = nc.Dataset(path, "w", format="NETCDF4")
    try:
        ds.createDimension("x", 50)
        ds.createDimension("y", 50)
        temp = ds.createVariable("temperature", "f4", ("x", "y"))
        temp[:] = np.asarray(data, dtype=np.float32)
    finally:
        ds.close()


def test_program_builds_runs_and_computes():
    # Preserve the original source-file assertion.
    assert_regular_file(SOURCE)

    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    # Require actual Go concurrency constructs rather than an unrelated program.
    scrubbed = re.sub(r"/\*.*?\*/|//[^\n]*|`[^`]*`|\"(?:\\.|[^\"\\])*\"", " ", source, flags=re.S)
    assert re.search(r"\bgo\s+(?:func\b|[A-Za-z_]\w*)", scrubbed), (
        "impute.go does not contain a goroutine launch for parallel grid updates."
    )
    assert ("WaitGroup" in scrubbed or re.search(r"\bchan\b|make\s*\(\s*chan\b", scrubbed)), (
        "impute.go does not contain synchronization for its parallel updates."
    )

    env = os.environ.copy()
    env.update({
        "HOME": HOME,
        "GOPATH": os.path.join(HOME, "go"),
        "GOCACHE": os.path.join(HOME, ".cache", "go-build"),
    })
    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd=HOME, env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, (
        f"impute.go did not build successfully.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    # Execute against the supplied dataset and preserve the original exact assertion.
    content = run_submission()
    expected_sum = "122500.0000"
    assert content == expected_sum, (
        f"Result file content is incorrect. Expected '{expected_sum}', got '{content}'."
    )

    # Replace the input with a derived case whose missing cells are isolated. This
    # checks that the program really reads NetCDF, preserves known cells, recognizes
    # -999, and performs the four-neighbor Jacobi update rather than printing a constant.
    data = np.fromfunction(lambda i, j: (i + 2 * j) % 4, (50, 50), dtype=int).astype(np.float32)
    missing = [(4, 7), (12, 31), (21, 16), (35, 42), (46, 24)]
    solved = data.copy()
    for i, j in missing:
        solved[i, j] = (data[i-1, j] + data[i+1, j] + data[i, j-1] + data[i, j+1]) / 4.0
        data[i, j] = np.float32(-999.0)
    expected = f"{float(np.sum(solved, dtype=np.float64)):.4f}"
    write_grid(data)
    assert run_submission() == expected

    # A coupled 2x2 hole needs repeated Jacobi iterations. Its exact limiting sum is
    # 5000; the convergence threshold permits only a very small residual error.
    data = np.full((50, 50), np.float32(2.0), dtype=np.float32)
    data[24:26, 24:26] = np.float32(-999.0)
    write_grid(data)
    iterative_result = float(run_submission())
    assert abs(iterative_result - 5000.0) <= 0.005, (
        f"Coupled missing block was not iterated to the required convergence tolerance: {iterative_result:.4f}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    score=1
else
    score=0
fi

cp /tmp/climate_grid.original.nc /home/user/climate_grid.nc
echo "$score" > /logs/verifier/reward.txt
