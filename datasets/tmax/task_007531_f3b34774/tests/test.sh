#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from pathlib import Path

CPP = Path('/home/user/pinns_data/generate_data.cpp')
WORKDIR = CPP.parent
BINARY = WORKDIR / 'generate_data'
BASELINE = WORKDIR / 'baseline.txt'
STATS = WORKDIR / 'stats.txt'
MESH = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 5.5, 6.0, 6.5, 7.0,
        7.5, 8.0, 8.5, 9.0, 9.5, 10.0]


def theoretical_temperatures():
    # Independent bisection oracle for T^3 + 2T - S = 0.
    roots = []
    for s in MESH:
        lo, hi = 0.0, 3.0
        for _ in range(200):
            mid = (lo + hi) / 2.0
            if mid ** 3 + 2.0 * mid < s:
                lo = mid
            else:
                hi = mid
        roots.append((lo + hi) / 2.0)
    return roots


def read_stats():
    assert STATS.is_file(), f'The output file {STATS} does not exist. Did you run your program?'
    with STATS.open('r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 2, f'Expected exactly 2 lines in {STATS}, found {len(lines)}.'
    return lines


def run_submission(baseline_values):
    BASELINE.write_text(''.join(f'{value:.12f}\n' for value in baseline_values))
    if STATS.exists():
        STATS.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=str(WORKDIR), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    return read_stats()


def expected_lines(baseline_values, roots):
    mse = sum((t - b) ** 2 for t, b in zip(roots, baseline_values)) / len(roots)
    status = 'Accepted' if mse < 0.05 else 'Rejected'
    return [f'MSE: {mse:.4f}', f'H0: {status}']


def test_complete_cpp_program():
    # Preserve the original existence and final-output assertions.
    assert CPP.is_file(), f'The C++ source file {CPP} does not exist.'
    assert not CPP.is_symlink(), f'{CPP} must be a C++ source file, not a symbolic link.'
    assert stat.S_ISREG(CPP.stat().st_mode), f'{CPP} is not a regular file.'
    initial_lines = read_stats()
    assert initial_lines[0] == 'MSE: 0.0100', (
        f"Expected first line to be 'MSE: 0.0100', but got '{initial_lines[0]}'."
    )
    assert initial_lines[1] == 'H0: Accepted', (
        f"Expected second line to be 'H0: Accepted', but got '{initial_lines[1]}'."
    )

    original_baseline = BASELINE.read_text()
    original_values = [float(x) for x in original_baseline.split()]
    assert len(original_values) == 16, 'The supplied baseline must contain 16 values.'

    compile_result = subprocess.run(
        ['g++', '-O3', 'generate_data.cpp', '-o', 'generate_data'],
        cwd=str(WORKDIR), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f'g++ failed with status {compile_result.returncode}.\n'
        f'stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}'
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Compilation did not produce an executable.'

    roots = theoretical_temperatures()
    try:
        # Re-run against the supplied baseline and retain the original exact checks.
        lines = run_submission(original_values)
        assert lines[0] == 'MSE: 0.0100', (
            f"Expected first line to be 'MSE: 0.0100', but got '{lines[0]}'."
        )
        assert lines[1] == 'H0: Accepted', (
            f"Expected second line to be 'H0: Accepted', but got '{lines[1]}'."
        )

        # A zero-error baseline verifies the equation solutions and 16-point mesh.
        zero_case = [float(f'{r:.12f}') for r in roots]
        assert run_submission(zero_case) == expected_lines(zero_case, roots)

        # Nonuniform perturbations verify that all baseline entries are read and
        # used in the MSE calculation; this case remains below the threshold.
        offsets_a = [0.02 * (i + 1) * (-1 if i % 2 else 1) for i in range(16)]
        case_a = [float(f'{r + d:.12f}') for r, d in zip(roots, offsets_a)]
        assert run_submission(case_a) == expected_lines(case_a, roots)

        # A distinct nonuniform case exercises the Rejected branch.
        offsets_b = [(0.21 + 0.01 * i) * (-1 if i % 3 == 0 else 1) for i in range(16)]
        case_b = [float(f'{r + d:.12f}') for r, d in zip(roots, offsets_b)]
        assert run_submission(case_b) == expected_lines(case_b, roots)
    finally:
        BASELINE.write_text(original_baseline)
        subprocess.run([str(BINARY)], cwd=str(WORKDIR), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10, check=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
