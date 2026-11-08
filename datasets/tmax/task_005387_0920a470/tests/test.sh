#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import secrets
import subprocess
import tempfile

import pytest

EXE_PATH = "/home/user/fit_data"
SOURCE_PATH = "/home/user/fit_data.c"
COEFFS_PATH = "/home/user/coeffs.txt"
DATA_PATH = "/home/user/data.h5"
VERIFIER_EXE = "/tmp/verifier_fit_data"


def run_program(path):
    return subprocess.run(
        [path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )


def parse_native_output(output):
    lines = output.strip().split("\n")
    assert len(lines) == 13, f"Expected exactly 13 output lines, found {len(lines)}."
    for i, line in enumerate(lines):
        assert re.fullmatch(r"-?\d+\.\d{6}", line), (
            f"Output line {i + 1} does not match the native %.6f format: {line!r}"
        )
    return [float(line) for line in lines]


def test_executable_exists():
    exe_path = EXE_PATH
    assert os.path.exists(exe_path), f"Compiled executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."
    assert os.path.isfile(exe_path) and not os.path.islink(exe_path), (
        f"{exe_path} must be a regular compiled executable."
    )
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not an ELF executable."


def test_source_builds():
    assert os.path.isfile(SOURCE_PATH), f"Modified source {SOURCE_PATH} is missing."
    result = subprocess.run(
        ["h5cc", SOURCE_PATH, "-o", VERIFIER_EXE, "-lgsl", "-lgslcblas", "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The submitted C source does not compile successfully:\n"
        + result.stdout
        + result.stderr
    )
    assert os.path.isfile(VERIFIER_EXE) and os.access(VERIFIER_EXE, os.X_OK)


def test_coeffs_txt_exists_and_format():
    coeffs_path = COEFFS_PATH
    assert os.path.exists(coeffs_path), f"{coeffs_path} is missing."

    with open(coeffs_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 13, f"Expected exactly 13 lines in {coeffs_path}, found {len(lines)}."

    for i, line in enumerate(lines):
        try:
            float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in {coeffs_path} is not a valid floating-point number: '{line}'")


def test_coeffs_are_actual_program_output():
    with open(COEFFS_PATH, "r") as f:
        saved_output = f.read()

    result = run_program(EXE_PATH)
    assert result.returncode == 0, (
        f"{EXE_PATH} failed when executed:\n{result.stdout}\n{result.stderr}"
    )
    parse_native_output(result.stdout)
    assert result.stdout == saved_output, (
        f"{COEFFS_PATH} is not the exact standard output produced by {EXE_PATH}."
    )


def test_coeffs_correctness():
    # We use the container's Python environment (which has numpy and h5py installed)
    # to read the HDF5 file and verify the math, as we are restricted to stdlib in the test suite itself.
    verify_script = """
import sys
import numpy as np
import h5py

try:
    with h5py.File('/home/user/data.h5', 'r') as f:
        x = f['x'][:]
        y = f['y'][:]

    X = np.vander(x, 13, increasing=True)
    A = X.T @ X
    B = X.T @ y
    A += 0.001 * np.eye(13)
    coeffs_ridge = np.linalg.solve(A, B)

    loaded_coeffs = np.loadtxt('/home/user/coeffs.txt')

    if len(loaded_coeffs) != 13:
        print(f"Expected 13 coefficients, got {len(loaded_coeffs)}")
        sys.exit(1)

    if not np.allclose(loaded_coeffs, coeffs_ridge, atol=1e-4):
        print("Coefficients do not match expected Ridge Regression values within tolerance.")
        sys.exit(1)

except Exception as e:
    print(f"Error during verification: {e}")
    sys.exit(2)
"""
    result = subprocess.run(["python3", "-c", verify_script], capture_output=True, text=True)

    if result.returncode == 2:
        pytest.fail(f"Verification script encountered an error:\n{result.stdout}\n{result.stderr}")
    elif result.returncode == 1:
        pytest.fail(f"Math verification failed:\n{result.stdout}")

    assert result.returncode == 0, "Unknown error occurred during coefficient verification."


def test_source_and_executable_implement_ridge_on_unseen_data():
    import h5py
    import numpy as np

    assert os.path.isfile(VERIFIER_EXE), "Verifier-built source executable is missing."

    fd, backup_path = tempfile.mkstemp(prefix="data_backup_", suffix=".h5")
    os.close(fd)
    shutil.copy2(DATA_PATH, backup_path)

    try:
        for _ in range(2):
            seed = secrets.randbits(128)
            rng = np.random.default_rng(seed)
            x = rng.uniform(-1.25, 1.25, 100)
            y = rng.normal(size=100)
            X = np.vander(x, 13, increasing=True)
            expected = np.linalg.solve(X.T @ X + 0.001 * np.eye(13), X.T @ y)

            for program in (VERIFIER_EXE, EXE_PATH):
                with h5py.File(DATA_PATH, "w") as f:
                    f.create_dataset("x", data=x)
                    f.create_dataset("y", data=y)

                result = run_program(program)
                assert result.returncode == 0, (
                    f"{program} failed on verifier-generated input:\n"
                    f"{result.stdout}\n{result.stderr}"
                )
                actual = np.asarray(parse_native_output(result.stdout))
                assert np.allclose(actual, expected, rtol=1e-5, atol=2e-5), (
                    f"{program} does not implement lambda=0.001 ridge regression "
                    "on verifier-generated input."
                )
    finally:
        os.replace(backup_path, DATA_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
