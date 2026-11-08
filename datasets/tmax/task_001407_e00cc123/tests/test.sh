#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import textwrap

import h5py
import numpy as np

SOURCE = "/home/user/regularize.cpp"
INPUT = "/home/user/data/input.h5"
OUTPUT = "/home/user/data/output.h5"
CI_FILE = "/home/user/data/trace_ci.txt"
EXE = "/tmp/submission_regularize"


def build_submission():
    assert os.path.isfile(SOURCE), "The file /home/user/regularize.cpp does not exist."
    text = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]H5Cpp\.h[>\"]", text), "regularize.cpp must use H5Cpp.h"
    assert re.search(r"std\s*::\s*mt19937\s+\w+\s*\(\s*42\s*\)", text), "regularize.cpp must declare std::mt19937 seeded with 42"
    assert re.search(r"uniform_real_distribution", text), "regularize.cpp must use a uniform_real_distribution"
    assert re.search(r"\b10000\b", text), "regularize.cpp must specify 10000 iterations"

    cmd = [
        "g++", "-std=c++17", "-O2", SOURCE, "-o", EXE,
        "-I/usr/include/hdf5/serial",
        "-L/usr/lib/x86_64-linux-gnu/hdf5/serial",
        "-lhdf5_cpp", "-lhdf5"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, "regularize.cpp failed to compile:\n" + result.stdout + result.stderr
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), "Compilation did not produce an executable"


def make_oracle_values():
    oracle_source = r'''
#include <algorithm>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>
int main() {
    constexpr int N = 10000;
    constexpr int D = 10;
    std::mt19937 gen(42);
    std::uniform_real_distribution<double> dist(0.0, 0.01);
    double sums[D] = {};
    std::vector<double> traces;
    traces.reserve(N);
    for (int i = 0; i < N; ++i) {
        double t = 0.0;
        for (int j = 0; j < D; ++j) {
            double x = dist(gen);
            sums[j] += x;
            t += x;
        }
        traces.push_back(t);
    }
    std::sort(traces.begin(), traces.end());
    std::cout << std::setprecision(17);
    for (int j = 0; j < D; ++j) std::cout << sums[j] / N << "\n";
    for (double x : traces) std::cout << x << "\n";
}
'''
    with open("/tmp/trace_oracle.cpp", "w") as f:
        f.write(oracle_source)
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "/tmp/trace_oracle.cpp", "-o", "/tmp/trace_oracle"],
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, "Verifier oracle failed to compile: " + result.stderr
    result = subprocess.run(["/tmp/trace_oracle"], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, "Verifier oracle failed to run"
    values = np.array([float(x) for x in result.stdout.split()], dtype=np.float64)
    assert values.size == 10010
    return values[:10], values[10:]


def replace_input(matrix):
    with h5py.File(INPUT, "w") as f:
        f.create_dataset("cov_matrix", data=np.asarray(matrix, dtype=np.float64), dtype="float64")


def run_submission():
    for path in (OUTPUT, CI_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run([EXE], cwd="/home/user", capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, "Compiled regularize.cpp failed to run:\n" + result.stdout + result.stderr
    assert os.path.isfile(OUTPUT), "The file /home/user/data/output.h5 does not exist."
    assert os.path.isfile(CI_FILE), "The file /home/user/data/trace_ci.txt does not exist."


def validate_outputs(orig, expected_means, sorted_trace_additions, require_original_ranges=False):
    with h5py.File(OUTPUT, "r") as f:
        assert "reg_matrix" in f, "Dataset 'reg_matrix' not found in output.h5"
        ds = f["reg_matrix"]
        assert ds.dtype == np.dtype("float64"), "reg_matrix must have HDF5 double type"
        reg = ds[:]

    assert reg.shape == orig.shape, f"Expected shape {orig.shape}, got {reg.shape}"
    diff = reg - orig
    off_diag = diff - np.diag(np.diag(diff))
    assert np.allclose(off_diag, 0, atol=1e-10, rtol=0), "Off-diagonal elements were modified"

    diags = np.diag(diff)
    assert np.all(diags > 0.004) and np.all(diags < 0.006), "Diagonal additions are outside the expected mean range"
    assert np.allclose(diags, expected_means, atol=1e-7, rtol=0), \
        f"Mean diagonal does not match 10000 seeded Monte Carlo iterations: got {diags}, expected {expected_means}"

    content = open(CI_FILE, "r").read().strip()
    fields = content.split(",")
    assert len(fields) == 2, f"Expected 2 comma-separated values, got {len(fields)}"
    try:
        lower, upper = map(float, fields)
    except Exception as exc:
        raise AssertionError(f"Failed to parse trace_ci.txt: {exc}")
    assert np.isfinite(lower) and np.isfinite(upper) and lower <= upper

    orig_trace = float(np.trace(orig))
    # Permit the common floor, nearest-rank, and linearly interpolated percentile
    # conventions. All valid results lie between the adjacent order statistics.
    tol = 1e-4  # also permits ordinary C++ stream precision in the text file
    expected_lower_interval = (orig_trace + sorted_trace_additions[249],
                               orig_trace + sorted_trace_additions[250])
    expected_upper_interval = (orig_trace + sorted_trace_additions[9749],
                               orig_trace + sorted_trace_additions[9750])
    assert expected_lower_interval[0] - tol <= lower <= expected_lower_interval[1] + tol, \
        f"Lower trace percentile {lower} does not match the seeded simulation"
    assert expected_upper_interval[0] - tol <= upper <= expected_upper_interval[1] + tol, \
        f"Upper trace percentile {upper} does not match the seeded simulation"

    if require_original_ranges:
        assert orig_trace + 0.02 < lower < orig_trace + 0.045, "Lower bound is out of the original expected range"
        assert orig_trace + 0.055 < upper < orig_trace + 0.08, "Upper bound is out of the original expected range"


def test_compiled_program_performs_seeded_simulation():
    build_submission()
    expected_means, sorted_trace_additions = make_oracle_values()
    with h5py.File(INPUT, "r") as f:
        original = f["cov_matrix"][:]

    # Exercise the compiled artifact on an input unavailable when the agent ran,
    # so pre-created output files and hard-coded original-matrix answers cannot pass.
    rng = np.random.default_rng(78123)
    challenge = rng.normal(size=(10, 10))
    challenge = (challenge + challenge.T) / 2.0

    challenge_error = None
    try:
        replace_input(challenge)
        run_submission()
        validate_outputs(challenge, expected_means, sorted_trace_additions)
    except BaseException as exc:
        challenge_error = exc
    finally:
        # Restore the instructed input and require the submitted executable to
        # regenerate the final deliverables for that real input.
        replace_input(original)
        run_submission()
        validate_outputs(original, expected_means, sorted_trace_additions, require_original_ranges=True)

    if challenge_error is not None:
        raise challenge_error
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
