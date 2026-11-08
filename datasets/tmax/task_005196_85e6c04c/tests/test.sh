#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import subprocess
import textwrap
import pytest

SIM_DIR = "/home/user/simulation"
POSTERIOR = "/home/user/posterior_mean.txt"


def test_clean_obs_txt_exists_and_correct():
    path = "/home/user/clean_obs.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you save the cleaned data?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected 5 lines of data in {path}, got {len(lines)}."

    expected_lines = [
        "0.1 0.11",
        "0.2 0.55",
        "0.5 0.88",
        "0.8 0.22",
        "0.9 0.33"
    ]

    for i, expected in enumerate(expected_lines):
        parts = lines[i].split()
        assert len(parts) == 2, f"Line {i+1} in {path} does not have exactly 2 columns."

        try:
            x_val = float(parts[0])
            y_val = float(parts[1])
            exp_x, exp_y = map(float, expected.split())
            assert math.isclose(x_val, exp_x, rel_tol=1e-5), f"Line {i+1} x-value mismatch: got {x_val}, expected {exp_x}"
            assert math.isclose(y_val, exp_y, rel_tol=1e-5), f"Line {i+1} y-value mismatch: got {y_val}, expected {exp_y}"
        except ValueError:
            pytest.fail(f"Could not parse floats from line {i+1} in {path}: '{lines[i]}'")


def test_solver_cpp_modified():
    path = "/home/user/simulation/solver.cpp"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "1e-5" in content or "0.00001" in content, "Could not find the regularization term '1e-5' in solver.cpp."

    assert re.search(r'A\[[^\]]+\]\[[^\]]+\]\s*\+?=\s*(.*1e-5|.*0\.00001)', content) or \
           re.search(r'A\[[^\]]+\]\[[^\]]+\]\s*=\s*A\[[^\]]+\]\[[^\]]+\]\s*\+\s*(1e-5|0\.00001)', content), \
           "Could not find the exact logic adding 1e-5 to the matrix A in solver.cpp."


def test_compiled_executable_exists():
    path = "/home/user/simulation/mcmc_sim"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the code?"
    assert os.access(path, os.X_OK), f"{path} is not executable."


def _reference_solve(matrix, rhs):
    a = [row[:] for row in matrix]
    b = rhs[:]
    n = len(a)
    for i in range(n):
        a[i][i] += 1e-5

    for i in range(n):
        pivot = max(range(i, n), key=lambda r: abs(a[r][i]))
        assert abs(a[pivot][i]) > 1e-14
        if pivot != i:
            a[i], a[pivot] = a[pivot], a[i]
            b[i], b[pivot] = b[pivot], b[i]
        for k in range(i + 1, n):
            term = a[k][i] / a[i][i]
            for j in range(i, n):
                a[k][j] -= term * a[i][j]
            b[k] -= term * b[i]

    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        x[i] = (b[i] - sum(a[i][j] * x[j] for j in range(i + 1, n))) / a[i][i]
    return x


def test_solver_behavior_adds_exact_ridge_to_every_diagonal():
    harness = r'''
#include "solver.h"
#include <iomanip>
#include <iostream>
#include <vector>

static void run(const std::vector<std::vector<double>>& src,
                const std::vector<double>& rhs) {
    int n = static_cast<int>(src.size());
    double** a = new double*[n];
    double* b = new double[n];
    double* x = new double[n];
    for (int i = 0; i < n; ++i) {
        a[i] = new double[n];
        b[i] = rhs[i];
        for (int j = 0; j < n; ++j) a[i][j] = src[i][j];
    }
    solve_system(a, b, n, x);
    std::cout << std::setprecision(17);
    for (int i = 0; i < n; ++i) {
        if (i) std::cout << ' ';
        std::cout << x[i];
    }
    std::cout << '\n';
    for (int i = 0; i < n; ++i) delete[] a[i];
    delete[] a;
    delete[] b;
    delete[] x;
}

int main() {
    run({{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}},
        {1.0, -2.0, 0.5});
    run({{2.0, 0.0, 0.0}, {0.0, 3.0, 0.0}, {0.0, 0.0, 4.0}},
        {4.0, 9.0, -8.0});
    run({{4.0, 1.0, -1.0}, {2.0, 5.0, 1.0}, {1.0, -2.0, 6.0}},
        {3.0, -1.0, 7.0});
    return 0;
}
'''
    harness_path = "/tmp/solver_harness.cpp"
    binary_path = "/tmp/solver_harness"
    with open(harness_path, "w") as f:
        f.write(harness)

    built = subprocess.run(
        ["g++", "-std=c++11", "-I", SIM_DIR, harness_path,
         os.path.join(SIM_DIR, "solver.cpp"), "-o", binary_path],
        text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, f"solver.cpp failed to compile with a test harness:\n{built.stderr}"

    ran = subprocess.run([binary_path], text=True, capture_output=True, timeout=30)
    assert ran.returncode == 0, f"The submitted solver failed when executed:\n{ran.stderr}"

    matrices = [
        [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]],
        [[2.0, 0.0, 0.0], [0.0, 3.0, 0.0], [0.0, 0.0, 4.0]],
        [[4.0, 1.0, -1.0], [2.0, 5.0, 1.0], [1.0, -2.0, 6.0]],
    ]
    rhs_values = [[1.0, -2.0, 0.5], [4.0, 9.0, -8.0], [3.0, -1.0, 7.0]]
    lines = [line for line in ran.stdout.splitlines() if line.strip()]
    assert len(lines) == len(matrices), f"Unexpected solver harness output: {ran.stdout!r}"

    for case, (line, matrix, rhs) in enumerate(zip(lines, matrices, rhs_values), 1):
        try:
            actual = [float(v) for v in line.split()]
        except ValueError:
            pytest.fail(f"Non-numeric solver output in case {case}: {line!r}")
        expected = _reference_solve(matrix, rhs)
        assert len(actual) == len(expected)
        for i, (got, want) in enumerate(zip(actual, expected)):
            assert math.isfinite(got), f"Solver returned a non-finite value in case {case}, element {i}."
            assert math.isclose(got, want, rel_tol=1e-10, abs_tol=1e-7), \
                f"Solver result mismatch in case {case}, element {i}: got {got}, expected {want}. The ridge must be exactly 1e-5 on every diagonal before elimination."


def _expected_posterior_mean():
    state = 1
    alpha = 1.0
    total = 0.0

    def next_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) & ((1 << 64) - 1)
        return ((state >> 16) & 32767) / 32768.0

    for i in range(10000):
        proposed = alpha + (next_rand() - 0.5) * 0.1
        if i == 50:
            proposed = 0.0
        next_rand()  # acceptance draw; the correctly regularized model accepts here
        alpha = proposed
        if i >= 2000:
            total += alpha
    return total / 8000.0


def _read_posterior():
    assert os.path.isfile(POSTERIOR), "The simulation did not generate posterior_mean.txt."
    with open(POSTERIOR, "r") as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        pytest.fail(f"Could not parse the generated posterior mean: {content!r}")


def _assert_expected_posterior(value, label):
    expected = _expected_posterior_mean()
    assert math.isfinite(value), f"{label} produced a non-finite posterior mean."
    assert math.isclose(value, expected, rel_tol=2e-5, abs_tol=2e-6), \
        f"{label} produced posterior mean {value}, expected {expected}."


def test_execute_submitted_and_rebuilt_simulation():
    executable = os.path.join(SIM_DIR, "mcmc_sim")
    if os.path.exists(POSTERIOR):
        os.remove(POSTERIOR)
    ran = subprocess.run([executable], cwd=SIM_DIR, text=True, capture_output=True, timeout=30)
    assert ran.returncode == 0, f"mcmc_sim failed when executed:\n{ran.stderr}"
    _assert_expected_posterior(_read_posterior(), "The submitted mcmc_sim executable")

    rebuilt = "/tmp/mcmc_sim_rebuilt"
    built = subprocess.run(
        ["g++", "main.cpp", "solver.cpp", "-o", rebuilt],
        cwd=SIM_DIR, text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, f"The submitted simulation sources failed to compile:\n{built.stderr}"

    if os.path.exists(POSTERIOR):
        os.remove(POSTERIOR)
    reran = subprocess.run([rebuilt], cwd=SIM_DIR, text=True, capture_output=True, timeout=30)
    assert reran.returncode == 0, f"The rebuilt simulation failed when executed:\n{reran.stderr}"
    _assert_expected_posterior(_read_posterior(), "The simulation rebuilt from the submitted sources")


def test_posterior_mean_exists_and_valid():
    path = "/home/user/posterior_mean.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did the simulation run successfully?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    try:
        val = float(content)
        assert math.isfinite(val), f"Posterior mean in {path} is not finite (got {val})."
        assert val != 0.0, "Posterior mean is exactly 0.0, which is unexpected for this simulation."
    except ValueError:
        pytest.fail(f"Could not parse a valid float from {path}. Content: '{content}'")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
