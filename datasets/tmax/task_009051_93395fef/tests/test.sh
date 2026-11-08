#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

import h5py
import numpy as np
import pytest

CPP_PATH = "/home/user/process_signals.cpp"
EXE_PATH = "/home/user/process_signals"
INPUT_PATH = "/home/user/input_data.h5"
REFERENCE_PATH = "/home/user/reference.csv"
RESULT_PATH = "/home/user/profiling_results.json"


def make_case(case_number):
    # Generate fresh, verifier-only inputs so a precomputed or self-reported answer
    # cannot pass. Sizes vary to ensure dimensions are read from HDF5.
    seed = int.from_bytes(secrets.token_bytes(16), "little")
    rng = np.random.default_rng(seed)
    n = 15 + case_number * 2
    m = 37 + case_number * 4
    dt = 0.01

    t = np.arange(m, dtype=np.float64) * dt
    a = np.empty((n, m), dtype=np.float64)
    for i in range(n):
        f1 = rng.uniform(0.4, 2.5)
        f2 = rng.uniform(2.7, 5.0)
        phase = rng.uniform(-np.pi, np.pi)
        a[i] = (np.sin(2.0 * np.pi * f1 * t + phase)
                + 0.25 * np.cos(2.0 * np.pi * f2 * t)
                + 0.03 * rng.standard_normal(m))

    with h5py.File(INPUT_PATH, "w") as f:
        f.create_dataset("/raw_signals", data=a, dtype="float64")

    d = np.empty_like(a)
    d[:, 1:-1] = (a[:, 2:] - a[:, :-2]) / (2.0 * dt)
    d[:, 0] = (a[:, 1] - a[:, 0]) / dt
    d[:, -1] = (a[:, -1] - a[:, -2]) / dt

    u, s, vt = np.linalg.svd(d, full_matrices=False)
    filtered = (u[:, :5] * s[:5]) @ vt[:5, :]
    integrals = dt * (0.5 * filtered[:, 0]
                      + filtered[:, 1:-1].sum(axis=1)
                      + 0.5 * filtered[:, -1])

    # Keep the true maximum below the original 1e-4 threshold, but make it
    # random and nonzero so reporting a fabricated zero does not pass.
    offsets = rng.uniform(2.0e-5, 8.0e-5, size=n)
    offsets *= rng.choice(np.array([-1.0, 1.0]), size=n)
    reference = integrals + offsets
    np.savetxt(REFERENCE_PATH, reference, fmt="%.17g")

    # Derive the expected value from exactly what was written to disk.
    written_reference = np.loadtxt(REFERENCE_PATH, dtype=np.float64)
    return float(np.max(np.abs(integrals - written_reference)))


def load_and_check_json(expected):
    assert os.path.isfile(RESULT_PATH), f"Profiling results JSON is missing: {RESULT_PATH}"
    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("profiling_results.json is not a valid JSON file.")

    assert "num_threads_used" in data, "Key 'num_threads_used' is missing from JSON."
    assert "max_absolute_error" in data, "Key 'max_absolute_error' is missing from JSON."
    assert len(data.keys()) == 2, f"JSON should contain exactly two keys, found: {list(data.keys())}"
    assert data["num_threads_used"] == 4, f"Expected 4 threads, but got: {data['num_threads_used']}"

    mae = data["max_absolute_error"]
    assert isinstance(mae, (int, float)) and not isinstance(mae, bool), "max_absolute_error must be a number."
    assert np.isfinite(mae), "max_absolute_error must be finite."
    assert abs(mae) < 1e-4, f"max_absolute_error is too high: {mae} (expected < 1e-4)"
    assert abs(float(mae) - expected) < 2e-8, (
        f"Reported max_absolute_error {mae} does not match the independently "
        f"computed value {expected}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(CPP_PATH), f"C++ source file is missing: {CPP_PATH}"
    assert os.path.isfile(EXE_PATH), f"Executable file is missing: {EXE_PATH}"
    assert os.access(EXE_PATH, os.X_OK), f"File is not executable: {EXE_PATH}"

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"

    for case_number in range(2):
        expected = make_case(case_number)
        try:
            os.remove(RESULT_PATH)
        except FileNotFoundError:
            pass

        completed = subprocess.run(
            [EXE_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, (
            f"process_signals exited with status {completed.returncode}. "
            f"stdout: {completed.stdout[-2000:]} stderr: {completed.stderr[-2000:]}"
        )
        load_and_check_json(expected)


def test_cpp_file_exists():
    path = "/home/user/process_signals.cpp"
    assert os.path.isfile(path), f"C++ source file is missing: {path}"


def test_source_uses_required_libraries_and_parallel_loops():
    with open(CPP_PATH, "r", errors="replace") as f:
        source = f.read()

    assert re.search(r"#\s*include\s*[<\"](?:[^>\"]*/)?(?:hdf5|H5Cpp|highfive)[^>\"]*[>\"]", source, re.I), \
        "C++ source does not include an HDF5/HighFive header"
    assert re.search(r"(?:H5Fopen|H5Dopen|H5::H5File|HighFive::File)", source), \
        "C++ source does not use an HDF5 file/dataset API"
    assert re.search(r"#\s*include\s*[<\"]Eigen/", source), \
        "C++ source does not include Eigen"
    assert re.search(r"Eigen::(?:JacobiSVD|BDCSVD)|(?:JacobiSVD|BDCSVD)\s*<", source), \
        "C++ source does not perform SVD using Eigen"

    omp_loops = re.findall(r"#\s*pragma\s+omp\s+parallel\s+for\b", source, re.I)
    assert len(omp_loops) >= 2, \
        "C++ source must use OpenMP parallel-for loops for differentiation and integration"
    assert re.search(r"omp_set_num_threads\s*\(\s*4\s*\)|num_threads\s*\(\s*4\s*\)", source), \
        "C++ source does not configure the OpenMP loops to use 4 threads"


def test_executable_exists():
    path = "/home/user/process_signals"
    assert os.path.isfile(path), f"Executable file is missing: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"


def test_profiling_results_json():
    path = "/home/user/profiling_results.json"
    assert os.path.isfile(path), f"Profiling results JSON is missing: {path}"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("profiling_results.json is not a valid JSON file.")

    assert "num_threads_used" in data, "Key 'num_threads_used' is missing from JSON."
    assert "max_absolute_error" in data, "Key 'max_absolute_error' is missing from JSON."

    # Check exact format requirement (only these two keys)
    assert len(data.keys()) == 2, f"JSON should contain exactly two keys, found: {list(data.keys())}"

    assert data["num_threads_used"] == 4, f"Expected 4 threads, but got: {data['num_threads_used']}"

    mae = data["max_absolute_error"]
    assert isinstance(mae, (int, float)), "max_absolute_error must be a number."
    assert abs(mae) < 1e-4, f"max_absolute_error is too high: {mae} (expected < 1e-4)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
