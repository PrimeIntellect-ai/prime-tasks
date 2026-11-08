#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_pipeline.sh"
PROJECT_PATH = "/home/user/diffusion_data"
BINARY_PATH = "/home/user/diffusion_data/target/release/diffusion_data"
HDF5_PATH = "/home/user/training_data.h5"


def test_run_pipeline_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_cargo_project_exists():
    cargo_toml = os.path.join(PROJECT_PATH, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Cargo project not found at {cargo_toml}."


def test_pipeline_builds_and_rust_program_generates_output():
    # Remove previously fabricated/stale artifacts so the submitted pipeline must
    # build the Rust executable and generate the HDF5 file during verification.
    for path in (HDF5_PATH, BINARY_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, (
        f"Pipeline failed:\n{result.stdout}\n{result.stderr}"
    )

    assert os.path.isfile(BINARY_PATH), (
        f"Release Rust executable was not built at {BINARY_PATH}."
    )
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", (
            f"{BINARY_PATH} is not an ELF executable."
        )

    # Execute the built Rust artifact itself after deleting the pipeline output.
    # This ensures the project, rather than a pre-created dummy file, produces it.
    if os.path.lexists(HDF5_PATH):
        os.remove(HDF5_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT_PATH,
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, (
        f"Built Rust program failed:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(HDF5_PATH), (
        f"The built Rust program did not create {HDF5_PATH}."
    )


def test_hdf5_output_valid():
    assert os.path.exists(HDF5_PATH), f"The output file {HDF5_PATH} does not exist."

    validation_script = r'''
import numpy as np
import h5py
import sys

x = np.linspace(0, 1, 50)
data = []
for i in range(10):
    u = np.sin(np.pi * x * (i + 1)) + 0.5 * np.sin(3 * np.pi * x)
    u[0] = 0
    u[-1] = 0
    data.append(u)
data = np.array(data)

alpha = 0.01
dx = 1.0 / 49.0
dt = 0.0001
c = alpha * dt / (dx**2)

expected_res = []
for i in range(10):
    u = data[i].copy()
    while True:
        u_new = u.copy()
        for j in range(1, 49):
            u_new[j] = u[j] + c * (u[j+1] - 2*u[j] + u[j-1])
        diff = np.max(np.abs(u_new - u))
        u = u_new
        if diff < 1e-6:
            break
    expected_res.append(u)
expected_res = np.array(expected_res)

try:
    with h5py.File('/home/user/training_data.h5', 'r') as f:
        if list(f.keys()) != ['converged_states']:
            print(f"Expected only root dataset 'converged_states', got {list(f.keys())}")
            sys.exit(1)

        dataset = f['converged_states']
        if not isinstance(dataset, h5py.Dataset):
            print("'converged_states' is not a dataset.")
            sys.exit(1)
        if dataset.shape != (10, 50):
            print(f"Expected shape (10, 50), got {dataset.shape}")
            sys.exit(1)
        if dataset.dtype != np.dtype(np.float64):
            print(f"Expected float64 data, got {dataset.dtype}")
            sys.exit(1)

        actual_res = dataset[:]
        if not np.all(np.isfinite(actual_res)):
            print("Output contains NaN or infinite values.")
            sys.exit(1)

        max_diff = np.max(np.abs(actual_res - expected_res))
        if not np.isfinite(max_diff) or max_diff >= 1e-5:
            print(f"Max difference {max_diff} exceeds tolerance 1e-5 or is non-finite.")
            sys.exit(1)

except Exception as e:
    print(f"Exception during validation: {e}")
    sys.exit(1)
'''
    result = subprocess.run(
        ["python3", "-c", validation_script],
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, (
        f"HDF5 validation failed:\n{result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
