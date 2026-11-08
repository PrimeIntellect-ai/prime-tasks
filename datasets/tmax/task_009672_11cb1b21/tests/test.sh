#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import time
import pytest

SOURCE = "/home/user/heat_opt.c"
PROGRAM = "/tmp/heat_opt_verified"
HARNESS = "/tmp/heat_opt_harness"


@pytest.fixture(scope="session")
def built_and_run():
    assert os.path.exists(SOURCE), f"File {SOURCE} does not exist."

    subprocess.run(
        ["gcc", "-O3", "-std=gnu11", SOURCE, "-lm", "-o", PROGRAM],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    start = time.monotonic()
    result = subprocess.run(
        [PROGRAM],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    elapsed = time.monotonic() - start

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"Expected exactly one output line from heat_opt, got: {result.stdout!r}"
    try:
        alpha = float(lines[0])
    except ValueError:
        pytest.fail(f"Program output is not a floating-point alpha: {lines[0]!r}")
    assert math.isfinite(alpha), f"Program emitted a non-finite alpha: {alpha}"

    harness_source = r'''
#define main submitted_heat_opt_main
#include "/home/user/heat_opt.c"
#undef main

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    double alpha = strtod(argv[1], NULL);
    double state[N];
    run_sim(alpha, state);
    for (int i = 0; i < N; ++i)
        printf("%.17g\n", state[i]);
    return 0;
}
'''
    with open("/tmp/heat_opt_harness.c", "w") as f:
        f.write(harness_source)
    subprocess.run(
        ["gcc", "-O3", "-std=gnu11", "/tmp/heat_opt_harness.c", "-lm", "-o", HARNESS],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    return lines[0], alpha, elapsed


def test_bottleneck_txt():
    bottleneck_path = "/home/user/bottleneck.txt"
    assert os.path.exists(bottleneck_path), f"File {bottleneck_path} does not exist."
    with open(bottleneck_path, "r") as f:
        content = f.read().strip()
    assert "dense_lu_solve" in content, f"Expected 'dense_lu_solve' in bottleneck.txt, got: {content}"


def test_solution_txt(built_and_run):
    output_text, program_alpha, _ = built_and_run
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), f"File {solution_path} does not exist."
    with open(solution_path, "r") as f:
        content = f.read().strip()

    try:
        alpha_val = float(content)
    except ValueError:
        assert False, f"Could not parse float from solution.txt: {content}"

    expected_alpha = 0.027878
    assert math.isclose(alpha_val, expected_alpha, rel_tol=1e-2, abs_tol=1e-3), \
        f"Expected alpha value close to {expected_alpha}, got {alpha_val}"
    assert content == output_text, \
        f"solution.txt must contain exactly the alpha emitted by the compiled program; file={content!r}, output={output_text!r}"
    assert alpha_val == program_alpha


def test_heat_opt_c_modified():
    source_path = "/home/user/heat_opt.c"
    assert os.path.exists(source_path), f"File {source_path} does not exist."
    with open(source_path, "r") as f:
        content = f.read()

    original_loop_snippet = "for (int j = 0; j < i; j++)"
    count_original_loops = content.count(original_loop_snippet)
    assert count_original_loops < 3, "It appears the dense LU decomposition is still present in heat_opt.c."


def test_compiled_program_finishes_quickly(built_and_run):
    _, _, elapsed = built_and_run
    assert elapsed < 30.0, f"Optimized program took too long to run: {elapsed:.3f}s"


@pytest.mark.parametrize("alpha", [0.005, 0.042, 0.09])
def test_backward_euler_tridiagonal_solutions(alpha, built_and_run):
    result = subprocess.run(
        [HARNESS, format(alpha, ".17g")],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    values = [float(line) for line in result.stdout.splitlines() if line.strip()]
    assert len(values) == 300, f"run_sim returned {len(values)} values instead of 300"
    assert all(math.isfinite(v) for v in values), "run_sim produced non-finite values"

    # The initial sine vector is an eigenvector of the discrete Dirichlet
    # Laplacian. Independently derive the exact Backward Euler result rather
    # than trusting solution.txt or another submitted artifact.
    n = 300
    steps = 100
    dx = 1.0 / (n - 1)
    dt = 0.5 / steps
    r = alpha * dt / (dx * dx)
    eigenvalue_factor = 4.0 * math.sin(math.pi / (2.0 * (n - 1))) ** 2
    amplification = (1.0 / (1.0 + r * eigenvalue_factor)) ** steps
    expected = [math.sin(math.pi * i / (n - 1)) * amplification for i in range(n)]

    max_error = max(abs(got - want) for got, want in zip(values, expected))
    assert max_error < 1e-8, \
        f"Incorrect Backward Euler tridiagonal solve for alpha={alpha}: max error {max_error}"
    assert abs(values[0]) < 1e-12 and abs(values[-1]) < 1e-12, \
        "Dirichlet boundary values were not preserved"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
