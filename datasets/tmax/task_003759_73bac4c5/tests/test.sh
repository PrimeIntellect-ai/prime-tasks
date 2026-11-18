#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import pytest

def test_best_parameters_file_exists():
    """Test that the best_parameters.txt file exists."""
    file_path = "/home/user/best_parameters.txt"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. Did the C++ program run successfully?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_best_parameters_content():
    """Test that the best_parameters.txt file contains the correct A, D, and MSE."""
    file_path = "/home/user/best_parameters.txt"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content != "", f"The file {file_path} is empty."

    # Split by whitespace
    parts = content.split()
    assert len(parts) == 3, f"Expected exactly 3 space-separated numbers in {file_path}, but found {len(parts)}."

    # Expected values
    expected_A = "3.1200"
    expected_D = "0.5300"
    expected_MSE = "0.0000"

    assert parts[0] == expected_A, f"Expected A={expected_A}, but got {parts[0]}."
    assert parts[1] == expected_D, f"Expected D={expected_D}, but got {parts[1]}."

    # MSE might be very small, but the requirement specifically asks for 4 decimal places
    # So it should be exactly "0.0000"
    assert parts[2] == expected_MSE, f"Expected MSE={expected_MSE}, but got {parts[2]}."

def test_cpp_source_file_exists():
    """Test that the fit_model.cpp file exists."""
    file_path = "/home/user/fit_model.cpp"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. You must write the C++ program."
TEST_EOF

cat << 'CHECK_EOF' > /tmp/check_implementation.py
import os
import re
import shutil
import subprocess
import tempfile

import h5py
import numpy as np

SOURCE = "/home/user/fit_model.cpp"
DATA = "/home/user/experimental_data.h5"
OUTPUT = "/home/user/best_parameters.txt"
BINARY = "/tmp/fit_model_verifier"

assert os.path.isfile(SOURCE), f"{SOURCE} must be a regular file"
with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
    source = f.read()

# Ignore pragmas merely placed in comments and require an actual OpenMP work/parallel pragma.
code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
code = re.sub(r"//[^\n]*", "", code)
assert re.search(r"^[ \t]*#[ \t]*pragma[ \t]+omp[ \t]+(?:parallel|for)\b", code, re.M), \
    "fit_model.cpp does not contain an OpenMP parallel/worksharing pragma"

compiler = shutil.which("h5c++")
assert compiler, "h5c++ is unavailable"
compile_result = subprocess.run(
    [compiler, "-std=c++17", "-O2", "-fopenmp", SOURCE, "-o", BINARY],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
)
assert compile_result.returncode == 0, "Compilation failed:\n" + compile_result.stdout
assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable"

nm = subprocess.run(["nm", "-u", BINARY], text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=20)
assert re.search(r"\b(?:GOMP_|omp_)", nm.stdout), \
    "The compiled program contains no OpenMP runtime references"

def run_program():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "2"
    result = subprocess.run([BINARY], cwd="/home/user", env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=90)
    assert result.returncode == 0, "Program execution failed:\n" + result.stdout
    assert os.path.isfile(OUTPUT), "Executing the program did not create best_parameters.txt"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.fullmatch(r"-?\d+\.\d{4} -?\d+\.\d{4} -?\d+\.\d{4}\n?", content), \
        f"Output is not exactly one line of three values with four decimals: {content!r}"
    return content.strip()

# Rebuilding and executing against the supplied data must reproduce the original assertion.
assert run_program() == "3.1200 0.5300 0.0000", \
    "The compiled program did not produce the expected result for the supplied data"

backup_fd, backup = tempfile.mkstemp(suffix=".h5")
os.close(backup_fd)
shutil.copy2(DATA, backup)

A_grid = np.linspace(1.0, 5.0, 101, dtype=np.float64)
D_grid = np.linspace(0.1, 1.0, 91, dtype=np.float64)

def expected_result(x, t, u):
    best = None
    for A in A_grid:
        for D in D_grid:
            model = (A / np.sqrt(t[:, None])) * np.exp(
                -(x[None, :] ** 2) / (4.0 * D * t[:, None])
            )
            mse = float(np.mean((model - u) ** 2))
            if best is None or mse < best[0]:
                best = (mse, float(A), float(D))
    return f"{best[1]:.4f} {best[2]:.4f} {best[0]:.4f}"

try:
    # Runtime-generated, differently shaped datasets prevent a hardcoded answer and
    # force the executable to read x, t, and u and perform the specified discrete search.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    cases = [
        (31, 13, rng.uniform(1.45, 2.35), rng.uniform(0.18, 0.38)),
        (24, 17, rng.uniform(4.15, 4.75), rng.uniform(0.68, 0.91)),
    ]
    for nx, nt, a_true, d_true in cases:
        x = np.sort(rng.uniform(-7.0, 7.0, nx)).astype(np.float64)
        t = np.sort(rng.uniform(0.7, 8.5, nt)).astype(np.float64)
        u = (a_true / np.sqrt(t[:, None])) * np.exp(
            -(x[None, :] ** 2) / (4.0 * d_true * t[:, None])
        )
        u += rng.normal(0.0, 0.025, size=u.shape)
        with h5py.File(DATA, "w") as f:
            f.create_dataset("x", data=x, dtype="float64")
            f.create_dataset("t", data=t, dtype="float64")
            f.create_dataset("u", data=u, dtype="float64")
        expected = expected_result(x, t, u)
        actual = run_program()
        assert actual == expected, \
            f"Grid-search result is incorrect for generated HDF5 input: expected {expected}, got {actual}"
finally:
    shutil.copy2(backup, DATA)
    os.unlink(backup)
CHECK_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/check_implementation.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
