#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import textwrap
import time

HEADER = "/home/user/local/include/svd.h"
LIB_CANDIDATES = [
    "/home/user/local/lib/libsvd_fast.so",
    "/home/user/local/lib64/libsvd_fast.so",
]
RUN_TEST = "/home/user/run_test"
METRICS = "/home/user/metrics.json"


def local_library():
    for path in LIB_CANDIDATES:
        if os.path.isfile(path):
            return path
    return None


def assert_elf(path, description):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{description} at {path} is not an ELF binary"


def linked_to_local_library(executable, lib_path, env):
    result = subprocess.run(
        ["ldd", executable], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, f"ldd failed for {executable}:\n{result.stdout}"
    resolved = os.path.realpath(lib_path)
    return any(resolved == os.path.realpath(token)
               for line in result.stdout.splitlines()
               for token in line.replace("=>", " ").split()
               if token.startswith("/"))


def read_metrics(path):
    with open(path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Could not parse {path} as valid JSON: {exc}")

    assert "reconstruction_error" in metrics, "Metric 'reconstruction_error' is missing from metrics.json"
    assert "execution_time" in metrics, "Metric 'execution_time' is missing from metrics.json"
    recon_err = float(metrics["reconstruction_error"])
    exec_time = float(metrics["execution_time"])
    assert math.isfinite(recon_err) and recon_err >= 0.0, "Reconstruction error must be finite and non-negative"
    assert math.isfinite(exec_time) and exec_time >= 0.0, "Execution time must be finite and non-negative"
    assert recon_err <= 1e-7, (
        f"Reconstruction error {recon_err} is too high! Threshold is <= 1e-07. "
        "The algorithm precision has not been properly restored."
    )
    assert exec_time <= 1.5, (
        f"Execution time {exec_time}s is too high! Threshold is <= 1.5s. "
        "The build optimization has not been properly restored."
    )


def test_installed_artifacts_and_regression_executable():
    assert os.path.exists(HEADER), f"Header file not installed at {HEADER}"
    lib_path = local_library()
    assert lib_path is not None, (
        "Shared library libsvd_fast.so not found in /home/user/local/lib/ or /home/user/local/lib64/"
    )
    assert os.path.exists(RUN_TEST), f"Compiled test executable not found at {RUN_TEST}"
    assert os.access(RUN_TEST, os.X_OK), f"File at {RUN_TEST} is not executable"
    assert_elf(lib_path, "Installed shared library")
    assert_elf(RUN_TEST, "Regression executable")

    lib_dir = os.path.dirname(lib_path)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = lib_dir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    assert linked_to_local_library(RUN_TEST, lib_path, env), (
        f"{RUN_TEST} is not dynamically linked to the installed {lib_path}"
    )

    if os.path.exists(METRICS):
        os.remove(METRICS)
    started = time.time_ns()
    result = subprocess.run(
        [RUN_TEST], cwd="/home/user", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"Regression executable failed:\n{result.stdout}"
    assert os.path.isfile(METRICS), f"Metrics file not found at {METRICS}. Did you run the regression test?"
    assert os.stat(METRICS).st_mtime_ns >= started, "metrics.json was not freshly produced by run_test"
    read_metrics(METRICS)


def test_library_with_verifier_generated_regression():
    lib_path = local_library()
    assert lib_path is not None
    lib_dir = os.path.dirname(lib_path)
    source = r'''
#include "svd.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

int main() {
    const int n = 150;
    std::vector<std::vector<double>> A(n, std::vector<double>(n));
    std::mt19937 gen(42);
    std::normal_distribution<double> dist(0.0, 1.0);
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            A[i][j] = dist(gen);

    std::vector<std::vector<double>> U, V;
    std::vector<double> S;
    const auto start = std::chrono::high_resolution_clock::now();
    compute_svd(A, U, S, V);
    const auto end = std::chrono::high_resolution_clock::now();
    const double elapsed = std::chrono::duration<double>(end - start).count();

    if (U.size() != n || V.size() != n || S.size() != n) return 2;
    for (int i = 0; i < n; ++i)
        if (U[i].size() != n || V[i].size() != n) return 3;

    double error2 = 0.0;
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            double value = 0.0;
            for (int k = 0; k < n; ++k)
                value += U[i][k] * S[k] * V[j][k];
            const double d = A[i][j] - value;
            error2 += d * d;
        }
    }

    double max_orthogonality_error = 0.0;
    for (int p = 0; p < n; ++p) {
        for (int q = p; q < n; ++q) {
            double dot = 0.0;
            for (int i = 0; i < n; ++i) dot += U[i][p] * U[i][q];
            const double expected = (p == q) ? 1.0 : 0.0;
            max_orthogonality_error = std::max(max_orthogonality_error, std::abs(dot - expected));
        }
    }

    std::cout << std::setprecision(17)
              << elapsed << " " << std::sqrt(error2) << " "
              << max_orthogonality_error << "\n";
    return 0;
}
'''
    source_path = "/tmp/verifier_regression.cpp"
    executable = "/tmp/verifier_regression"
    with open(source_path, "w") as f:
        f.write(textwrap.dedent(source))

    compile_result = subprocess.run([
        "g++", "-std=c++17", "-O2", source_path,
        "-I/home/user/local/include", "-L" + lib_dir,
        "-Wl,-rpath," + lib_dir, "-lsvd_fast", "-o", executable
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert compile_result.returncode == 0, (
        "Could not compile a regression against the installed header/library:\n" + compile_result.stdout
    )

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = lib_dir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    assert linked_to_local_library(executable, lib_path, env), "Verifier regression did not link to the installed library"
    result = subprocess.run(
        [executable], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"Installed library failed the verifier regression:\n{result.stdout}"
    try:
        elapsed, recon_error, orthogonality_error = map(float, result.stdout.strip().split())
    except ValueError:
        raise AssertionError(f"Unexpected verifier regression output: {result.stdout!r}")

    assert all(math.isfinite(x) and x >= 0.0 for x in
               (elapsed, recon_error, orthogonality_error)), "Library produced invalid numerical results"
    assert recon_error <= 1e-7, f"Verifier-measured reconstruction error {recon_error} exceeds 1e-7"
    assert orthogonality_error <= 1e-8, (
        f"Computed singular vectors are not orthogonal; maximum error is {orthogonality_error}"
    )
    assert elapsed <= 1.5, f"Verifier-measured SVD execution time {elapsed}s exceeds 1.5s"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
