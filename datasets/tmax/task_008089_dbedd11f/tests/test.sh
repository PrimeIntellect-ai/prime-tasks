#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

PROJECT = "/home/user/heat_solver"
EXECUTABLE = os.path.join(PROJECT, "heat_sim")


def jacobi_expected(nx, ny, tol, max_iter, initial_grid):
    grid = list(initial_grid)
    next_grid = list(grid)

    for iter_index in range(max_iter):
        max_error = 0.0
        for y in range(1, ny - 1):
            for x in range(1, nx - 1):
                val = 0.25 * (
                    grid[(y - 1) * nx + x]
                    + grid[(y + 1) * nx + x]
                    + grid[y * nx + x - 1]
                    + grid[y * nx + x + 1]
                )
                next_grid[y * nx + x] = val
                max_error = max(max_error, abs(val - grid[y * nx + x]))

        grid[:] = next_grid
        if max_error < tol:
            return iter_index, grid

    return max_iter, grid


def compute_expected_iterations():
    nx, ny = 20, 20
    grid = [0.0] * (nx * ny)
    for x in range(nx):
        grid[x] = 100.0
    return jacobi_expected(nx, ny, 0.001, 5000, grid)[0]


def test_grid_config_restored():
    config_path = os.path.join(PROJECT, "grid_config.txt")
    assert os.path.isfile(config_path), f"{config_path} is missing. Did you restore it from git history?"

    with open(config_path, "r") as f:
        content = f.read()

    assert "nx=20" in content, "grid_config.txt is missing expected nx=20 configuration"
    assert "ny=20" in content, "grid_config.txt is missing expected ny=20 configuration"
    assert "tol=0.001" in content, "grid_config.txt is missing expected tol=0.001 configuration"
    assert "max_iter=5000" in content, "grid_config.txt is missing expected max_iter=5000 configuration"


def test_makefile_fixed_and_executable_built():
    makefile_path = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing."

    subprocess.run(["make", "-C", PROJECT, "clean"], capture_output=True, text=True)
    for name in ("heat_sim", "main.o", "solver.o"):
        path = os.path.join(PROJECT, name)
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["make", "-C", PROJECT], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"make failed to build the executable. Output: {result.stderr}"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} was not built."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "heat_sim is not a compiled ELF executable."

    result = subprocess.run(
        [EXECUTABLE], cwd=PROJECT, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Running {EXECUTABLE} failed. Output: {result.stderr}"
    assert "Converged in" in result.stdout, "Executable output did not contain 'Converged in'."

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines, "Executable produced no output."
    match = re.fullmatch(r"Converged in (\d+) iterations", lines[-1])
    assert match, f"Unexpected final output line: {lines[-1]!r}"
    expected = compute_expected_iterations()
    assert int(match.group(1)) == expected, (
        f"Executable reported {match.group(1)} iterations, expected {expected}."
    )


def test_solver_implements_jacobi_and_tracks_convergence():
    harness_source = r'''
#include "solver.h"
#include <iomanip>
#include <iostream>
#include <vector>

int main() {
    int cases = 0;
    if (!(std::cin >> cases)) return 2;
    std::cout << std::setprecision(17);
    for (int c = 0; c < cases; ++c) {
        int nx, ny, max_iter;
        double tol;
        std::cin >> nx >> ny >> tol >> max_iter;
        std::vector<double> grid(nx * ny);
        for (double &v : grid) std::cin >> v;
        int iters = solve(nx, ny, tol, max_iter, grid.data());
        std::cout << "RESULT " << c << " " << iters;
        for (double v : grid) std::cout << " " << v;
        std::cout << "\n";
    }
    return 0;
}
'''

    rng = random.Random(914732)
    cases = []

    nx, ny = 8, 7
    grid = [0.0] * (nx * ny)
    for x in range(nx):
        grid[x] = 100.0
    cases.append((nx, ny, 0.01, 3000, grid))

    for nx, ny, tol, max_iter in ((7, 6, 0.017, 1800), (9, 5, 0.004, 2200)):
        grid = [rng.uniform(-8.0, 8.0) for _ in range(nx * ny)]
        for x in range(nx):
            grid[x] = rng.uniform(20.0, 90.0)
            grid[(ny - 1) * nx + x] = rng.uniform(-20.0, 15.0)
        for y in range(ny):
            grid[y * nx] = rng.uniform(5.0, 40.0)
            grid[y * nx + nx - 1] = rng.uniform(-10.0, 30.0)
        cases.append((nx, ny, tol, max_iter, grid))

    nx, ny = 6, 6
    grid = [rng.uniform(-30.0, 30.0) for _ in range(nx * ny)]
    cases.append((nx, ny, 1e-20, 4, grid))

    with tempfile.TemporaryDirectory() as tmp:
        harness_cpp = os.path.join(tmp, "solver_harness.cpp")
        harness_bin = os.path.join(tmp, "solver_harness")
        with open(harness_cpp, "w") as f:
            f.write(harness_source)

        compile_result = subprocess.run(
            [
                "g++", "-std=c++17", "-O0", "-I", PROJECT,
                harness_cpp, os.path.join(PROJECT, "solver.cpp"),
                "-o", harness_bin,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert compile_result.returncode == 0, (
            "solver.cpp could not be compiled with a direct solver harness: "
            + compile_result.stderr
        )

        input_tokens = [str(len(cases))]
        expected = []
        for nx, ny, tol, max_iter, grid in cases:
            input_tokens.extend((str(nx), str(ny), repr(tol), str(max_iter)))
            input_tokens.extend(repr(v) for v in grid)
            expected.append(jacobi_expected(nx, ny, tol, max_iter, grid))

        run = subprocess.run(
            [harness_bin],
            input=" ".join(input_tokens),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert run.returncode == 0, f"Direct solver execution failed: {run.stderr}"

    result_lines = [line for line in run.stdout.splitlines() if line.startswith("RESULT ")]
    assert len(result_lines) == len(cases), f"Unexpected solver harness output: {run.stdout!r}"

    for case_index, (line, (expected_iters, expected_grid)) in enumerate(zip(result_lines, expected)):
        fields = line.split()
        assert int(fields[1]) == case_index
        actual_iters = int(fields[2])
        actual_grid = [float(value) for value in fields[3:]]
        assert actual_iters == expected_iters, (
            f"Case {case_index}: solve returned {actual_iters}, expected {expected_iters}."
        )
        assert len(actual_grid) == len(expected_grid)
        for i, (actual, wanted) in enumerate(zip(actual_grid, expected_grid)):
            assert math.isfinite(actual), f"Case {case_index}: non-finite grid value at {i}."
            assert abs(actual - wanted) <= 1e-9 * max(1.0, abs(wanted)), (
                f"Case {case_index}: grid value {i} was {actual}, expected {wanted}."
            )


def test_result_file_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"{result_path} is missing. Did you write the final number of iterations to it?"

    with open(result_path, "r") as f:
        result_content = f.read().strip()

    expected_iters = compute_expected_iterations()
    assert re.fullmatch(r"\d+", result_content), "result.txt must contain just the integer iteration count."
    assert result_content == str(expected_iters), (
        f"Expected {expected_iters} in {result_path}, but found {result_content!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
