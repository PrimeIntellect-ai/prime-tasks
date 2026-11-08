#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

import h5py
import numpy as np
import pytest

CPP_FILE = "/home/user/analyze_spectra.cpp"
DATA_FILE = "/home/user/spectra.h5"
RESULT_FILE = "/home/user/svd_result.txt"
TEST_BIN = "/tmp/analyze_spectra_test"


def parse_output(stdout):
    output_str = stdout.strip()
    match = re.search(r"Leading Singular Value:\s*(\d+\.\d+)", output_str)
    assert match is not None, f"Could not parse the singular value from program output:\n{output_str}"
    return match.group(1)


def reference_leading_singular_value(data):
    # Compute an independent, high-precision reference after mean centering.
    data64 = np.asarray(data, dtype=np.float64)
    centered = data64 - data64.mean(axis=0)
    return float(np.linalg.svd(centered, compute_uv=False)[0])


def assert_close_to_reference(observed_text, expected):
    observed = float(observed_text)
    # Allow normal float/Eigen numerical error while still requiring the actual SVD.
    tolerance = max(0.005, abs(expected) * 1.0e-4)
    assert abs(observed - expected) <= tolerance, (
        f"Leading singular value is incorrect: got {observed_text}, "
        f"independent reference is {expected:.8f} (tolerance {tolerance:.8f})."
    )


def run_program():
    run_res = subprocess.run([TEST_BIN], capture_output=True, text=True)
    assert run_res.returncode == 0, f"Program execution failed:\n{run_res.stderr}"
    return parse_output(run_res.stdout)


def test_atomic_pragma_removed():
    assert os.path.exists(CPP_FILE), f"{CPP_FILE} does not exist."
    with open(CPP_FILE, 'r') as f:
        content = f.read()

    assert "#pragma omp atomic" not in content, "The atomic pragma was not removed from the C++ file."


def test_svd_result_format():
    assert os.path.exists(RESULT_FILE), f"{RESULT_FILE} does not exist."
    with open(RESULT_FILE, 'r') as f:
        content = f.read().strip()

    match = re.match(r"^\d+\.\d{5}$", content)
    assert match is not None, f"File {RESULT_FILE} must contain only a numeric value formatted to exactly 5 decimal places. Found: '{content}'"


def test_determinism_and_correctness():
    assert os.path.exists(CPP_FILE), f"{CPP_FILE} does not exist."
    assert os.path.exists(DATA_FILE), f"{DATA_FILE} does not exist."
    assert os.path.exists(RESULT_FILE), f"{RESULT_FILE} does not exist."

    with open(RESULT_FILE, 'r') as f:
        reported_val = f.read().strip()

    compile_cmd = [
        "g++", "-O3", "-fopenmp",
        "-I/usr/include/eigen3", "-I/usr/include/hdf5/serial",
        CPP_FILE,
        "-L/usr/lib/x86_64-linux-gnu/hdf5/serial", "-lhdf5",
        "-o", TEST_BIN
    ]

    compilation = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compilation.returncode == 0, f"Compilation failed:\n{compilation.stderr}"

    with h5py.File(DATA_FILE, "r") as f:
        assert "dataset" in f, "spectra.h5 does not contain the required 'dataset'."
        original_data = f["dataset"][:]
    assert original_data.shape == (1000, 500), "The dataset must have dimensions 1000x500."
    original_reference = reference_leading_singular_value(original_data)

    outputs = [run_program() for _ in range(3)]

    first_output = outputs[0]
    for out in outputs[1:]:
        assert out == first_output, "Program is still non-deterministic. Multiple runs produced different results."

    assert reported_val == first_output, f"The value in {RESULT_FILE} ({reported_val}) does not match the deterministic output of the program ({first_output})."
    assert_close_to_reference(first_output, original_reference)

    # Replace the input temporarily with an unpredictable dataset. This prevents a
    # fixed, self-reported value from passing and verifies that the program reads,
    # centers, and analyzes the HDF5 dataset it is given.
    backup_fd, backup_path = tempfile.mkstemp(prefix="spectra_backup_", suffix=".h5")
    os.close(backup_fd)
    shutil.copy2(DATA_FILE, backup_path)
    try:
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        scale = rng.uniform(0.35, 2.5)
        challenge = (rng.standard_normal((1000, 500)) * scale).astype(np.float32)
        challenge_reference = reference_leading_singular_value(challenge)

        with h5py.File(DATA_FILE, "w") as f:
            f.create_dataset("dataset", data=challenge)

        challenge_output = run_program()
        assert_close_to_reference(challenge_output, challenge_reference)
    finally:
        shutil.copy2(backup_path, DATA_FILE)
        os.unlink(backup_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
