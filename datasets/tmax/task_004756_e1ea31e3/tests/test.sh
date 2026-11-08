#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import h5py
import numpy as np

CPP_PATH = "/home/user/mc_sim.cpp"
PY_PATH = "/home/user/run_convergence.py"
BIN_PATH = "/home/user/mc_sim"
H5_PATH = "/home/user/convergence_results.h5"
NS = [1000, 10000, 50000, 100000]
SEED = 12345


def run_pipeline():
    result = subprocess.run(
        ["python3", PY_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"run_convergence.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_energies():
    values = []
    for n in NS:
        total = 0.0
        for i in range(n):
            x = (i * 137.0 + SEED) * 0.01
            total += math.sin(x) * math.cos(x * 2.5)
        values.append(total)
    return values


def check_hdf5(expected):
    assert os.path.isfile(H5_PATH), f"HDF5 output file {H5_PATH} is missing."
    with h5py.File(H5_PATH, "r") as f:
        assert set(f.keys()) == {"N_values", "energies"}, (
            f"The HDF5 root must contain exactly N_values and energies; got {list(f.keys())}"
        )
        assert isinstance(f["N_values"], h5py.Dataset), "N_values must be a dataset."
        assert isinstance(f["energies"], h5py.Dataset), "energies must be a dataset."
        assert f["N_values"].shape == (4,), "N_values must be a 1D dataset of length 4."
        assert f["energies"].shape == (4,), "energies must be a 1D dataset of length 4."
        assert f["N_values"].dtype.name == "int32", (
            f"N_values dtype mismatch: expected int32, got {f['N_values'].dtype.name}"
        )
        assert f["energies"].dtype.name == "float64", (
            f"energies dtype mismatch: expected float64, got {f['energies'].dtype.name}"
        )
        assert list(f["N_values"][:]) == NS, "N_values contents are incorrect."
        actual = list(f["energies"][:])
        assert len(actual) == len(expected)
        for i, (a, b) in enumerate(zip(actual, expected)):
            assert math.isclose(float(a), float(b), rel_tol=1e-12, abs_tol=1e-12), (
                f"Energy mismatch at index {i} (N={NS[i]}): expected {b}, got {a}"
            )


def run_binary(n, seed, threads):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    result = subprocess.run(
        [BIN_PATH, str(n), str(seed)],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    output = result.stdout.strip()
    assert output and len(output.splitlines()) == 1, f"Invalid executable output: {output!r}"
    value = float(output)
    assert math.isfinite(value), f"Non-finite executable output: {output!r}"
    return output, value


def test_complete_submission():
    # Preserve the original source and existence assertions.
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} is missing."
    with open(CPP_PATH, "r") as f:
        original_cpp = f.read()
    assert "#pragma omp parallel for" in original_cpp, (
        "The C++ program must retain the parallel for loop."
    )
    assert "compute_energy" in original_cpp, (
        "The C++ program must retain the compute_energy function."
    )
    assert os.path.isfile(PY_PATH), f"Python script {PY_PATH} is missing."

    # The submitted pipeline must itself compile the program and create the file.
    for path in (BIN_PATH, H5_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_pipeline()
    assert os.path.isfile(BIN_PATH), "The pipeline did not create /home/user/mc_sim."
    assert os.access(BIN_PATH, os.X_OK), "The compiled program is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The pipeline output is not a compiled ELF executable."
    check_hdf5(expected_energies())

    # Exercise the pipeline with a temporary instrumented source. This verifies that
    # it compiles mc_sim.cpp, runs the resulting executable for all required inputs,
    # parses stdout, and does not merely fabricate the known HDF5 answers.
    probe_log = "/tmp/mc_probe_calls.txt"
    probe_cpp = r'''#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <omp.h>

double compute_energy(int i, int seed) { return i * 0.125 + seed * 0.001; }

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    int n = std::atoi(argv[1]);
    int seed = std::atoi(argv[2]);
    std::ofstream log("/tmp/mc_probe_calls.txt", std::ios::app);
    log << n << " " << seed << "\n";
    double marker = n * 0.125 + seed * 0.001;
    #pragma omp parallel for
    for (int i = 0; i < 1; ++i) { marker += compute_energy(i, seed) * 0.0; }
    std::cout << std::setprecision(17) << marker << "\n";
    return 0;
}
'''
    probe_error = None
    try:
        with open(CPP_PATH, "w") as f:
            f.write(probe_cpp)
        for path in (BIN_PATH, H5_PATH, probe_log):
            if os.path.exists(path):
                os.remove(path)
        run_pipeline()
        probe_expected = [n * 0.125 + SEED * 0.001 for n in NS]
        check_hdf5(probe_expected)
        assert os.path.isfile(probe_log), "The pipeline never ran the compiled executable."
        with open(probe_log, "r") as f:
            calls = [tuple(map(int, line.split())) for line in f if line.strip()]
        for required in [(n, SEED) for n in NS]:
            assert required in calls, f"The pipeline did not run mc_sim with arguments {required}."
    except BaseException as exc:
        probe_error = exc
    finally:
        with open(CPP_PATH, "w") as f:
            f.write(original_cpp)
        for path in (BIN_PATH, H5_PATH):
            if os.path.exists(path):
                os.remove(path)
        restore = subprocess.run(
            ["python3", PY_PATH], cwd="/home/user", capture_output=True, text=True, timeout=180
        )
        assert restore.returncode == 0, (
            f"Pipeline failed after restoring submitted C++:\n{restore.stdout}\n{restore.stderr}"
        )
    if probe_error is not None:
        raise probe_error

    check_hdf5(expected_energies())

    # Execute the submitted compiled C++ on additional inputs and require identical
    # output across repeated runs and OpenMP thread counts.
    hidden_cases = [(137, 9), (4093, 54321), (100000, 12345)]
    for n, seed in hidden_cases:
        outputs = []
        for threads in (1, 2, 4):
            for _ in range(3):
                text, value = run_binary(n, seed, threads)
                outputs.append(text)
        assert len(set(outputs)) == 1, (
            f"Non-deterministic output for N={n}, seed={seed}: {outputs}"
        )

        expected = 0.0
        for i in range(n):
            x = (i * 137.0 + seed) * 0.01
            expected += math.sin(x) * math.cos(x * 2.5)
        assert math.isclose(float(outputs[0]), expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Incorrect executable result for N={n}, seed={seed}: "
            f"expected {expected}, got {outputs[0]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
