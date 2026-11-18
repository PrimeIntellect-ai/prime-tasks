#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
import pytest


def test_magic_seed_recovered():
    seed_file = '/home/user/magic_seed.txt'
    assert os.path.exists(seed_file), f"File {seed_file} does not exist."
    with open(seed_file, 'r') as f:
        seed = f.read().strip()
    expected_seed = "a1b2c3d4e5f678901234567890abcdef"
    assert seed == expected_seed, f"Incorrect magic seed in {seed_file}. Expected {expected_seed}, got {seed}"


def test_solver_bug_fixed():
    solver_path = '/home/user/nbody_relax/solver.c'
    assert os.path.exists(solver_path), f"File {solver_path} does not exist."
    with open(solver_path, 'r') as f:
        content = f.read()
    assert "int dfx" not in content, "The integer truncation bug 'int dfx' is still present in solver.c."

    # Exercise solve_root independently on unpredictable positive targets.
    harness_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include "solver.h"

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    double guess = strtod(argv[1], NULL);
    double target = strtod(argv[2], NULL);
    double result = solve_root(guess, target);
    printf("%.17g\n", result);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_c = os.path.join(td, 'solver_harness.c')
        harness_bin = os.path.join(td, 'solver_harness')
        with open(harness_c, 'w') as f:
            f.write(harness_source)
        compile_res = subprocess.run(
            ['gcc', '-I', '/home/user/nbody_relax', '-o', harness_bin,
             harness_c, solver_path, '-lm'],
            capture_output=True, text=True
        )
        assert compile_res.returncode == 0, f"Compilation of solver harness failed:\n{compile_res.stderr}"

        cases = [(10.0, 25.0), (3.0, 2.0), (20.0, 121.0)]
        for _ in range(7):
            target = 0.25 + secrets.randbelow(500000) / 1000.0
            guess = 0.5 + secrets.randbelow(40000) / 1000.0
            cases.append((guess, target))

        for guess, target in cases:
            run_res = subprocess.run(
                [harness_bin, repr(guess), repr(target)],
                capture_output=True, text=True, timeout=5
            )
            assert run_res.returncode == 0, (
                f"solve_root harness failed for guess={guess}, target={target}:\n{run_res.stderr}"
            )
            try:
                result = float(run_res.stdout.strip())
            except ValueError:
                pytest.fail(f"solve_root produced a non-numeric result: {run_res.stdout!r}")
            expected = math.sqrt(target)
            assert math.isfinite(result), "solve_root produced a non-finite result"
            assert abs(result - expected) <= 1e-5 * max(1.0, expected), (
                f"solve_root({guess}, {target}) returned {result}, expected {expected}"
            )


def test_mre_compiles_and_runs():
    mre_c = '/home/user/mre.c'
    solver_c = '/home/user/nbody_relax/solver.c'
    mre_bin = '/home/user/mre'

    assert os.path.exists(mre_c), f"File {mre_c} does not exist."

    # Preserve the original build assertion.
    compile_res = subprocess.run(
        ['gcc', '-o', mre_bin, mre_c, solver_c, '-lm'],
        capture_output=True,
        text=True
    )
    assert compile_res.returncode == 0, f"Compilation of MRE failed:\n{compile_res.stderr}"

    # Re-link with a private wrapper that makes the process fail unless the MRE
    # actually calls solve_root with the required initial values.
    probe_c = '/tmp/mre_solver_probe.c'
    with open(probe_c, 'w') as f:
        f.write(r'''
#include <math.h>
#include <unistd.h>

double __real_solve_root(double guess, double target);
static int saw_required_call = 0;

double __wrap_solve_root(double guess, double target) {
    if (fabs(guess - 10.0) < 1e-12 && fabs(target - 25.0) < 1e-12)
        saw_required_call = 1;
    return __real_solve_root(guess, target);
}

__attribute__((destructor)) static void verify_solver_was_called(void) {
    if (!saw_required_call)
        _exit(86);
}
''')

    wrapped_compile = subprocess.run(
        ['gcc', '-o', mre_bin, mre_c, solver_c, probe_c,
         '-Wl,--wrap=solve_root', '-lm'],
        capture_output=True, text=True
    )
    assert wrapped_compile.returncode == 0, (
        f"Compilation of instrumented MRE failed:\n{wrapped_compile.stderr}"
    )

    result_file = '/home/user/convergence_result.txt'
    if os.path.lexists(result_file):
        os.remove(result_file)

    run_res = subprocess.run([mre_bin], capture_output=True, text=True, timeout=5)
    assert run_res.returncode == 0, (
        f"Execution of {mre_bin} failed with exit code {run_res.returncode}:\n{run_res.stderr}"
    )


def test_convergence_result():
    result_file = '/home/user/convergence_result.txt'
    assert os.path.exists(result_file), f"File {result_file} does not exist."
    assert os.path.isfile(result_file), f"{result_file} is not a regular file."
    with open(result_file, 'r') as f:
        result = f.read().strip()
    assert result == "5.0000", f"Incorrect convergence result. Expected '5.0000', got '{result}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
