#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import stat
import subprocess
import time
import numpy as np

SIM_DIR = '/home/user/sim'
EXEC_PATH = os.path.join(SIM_DIR, 'mesh_sim')
FORCES_PATH = os.path.join(SIM_DIR, 'forces.txt')
SOLVER_PATH = os.path.join(SIM_DIR, 'solver.c')
MAIN_PATH = os.path.join(SIM_DIR, 'main.c')

TRUSTED_MAIN = r'''#include <stdio.h>
#include <stdlib.h>

void solve_system(int n, double *A, double *b, double *x);

int main() {
    int n = 1000;
    double *A = (double*)malloc(n * n * sizeof(double));
    double *b = (double*)malloc(n * sizeof(double));
    double *x = (double*)malloc(n * sizeof(double));

    // Generate SPD matrix
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            A[i*n + j] = (i == j) ? 2.0 : 0.1;
        }
        b[i] = 1.0;
    }

    solve_system(n, A, b, x);

    FILE *f = fopen("forces.txt", "w");
    if (f) {
        for (int i = 0; i < n; i++) {
            fprintf(f, "%.10lf\n", x[i]);
        }
        fclose(f);
    }

    free(A); free(b); free(x);
    return 0;
}
'''


def run_and_check(executable):
    if os.path.exists(FORCES_PATH):
        os.remove(FORCES_PATH)

    start = time.monotonic()
    result = subprocess.run(
        [executable], cwd=SIM_DIR, capture_output=True, timeout=5
    )
    elapsed = time.monotonic() - start

    assert result.returncode == 0, (
        f'Execution failed with return code {result.returncode}\n'
        f'Stderr: {result.stderr.decode(errors="replace")}'
    )
    assert elapsed < 3.0, (
        f'Execution time {elapsed:.2f}s is too slow '
        f'(expected < 3.0s for >= 5x speedup)'
    )
    assert os.path.isfile(FORCES_PATH), 'Execution did not generate forces.txt'

    values = np.loadtxt(FORCES_PATH)
    expected = np.full(1000, 1.0 / (2.0 + 0.1 * 999.0))
    assert values.shape == expected.shape, (
        f'Shape mismatch: expected {expected.shape}, got {values.shape}'
    )
    assert np.all(np.isfinite(values)), 'forces.txt contains non-finite values'
    mse = np.mean((expected - values) ** 2)
    assert mse < 1e-4, f'MSE {mse} is too high (threshold < 1e-4)'


def test_final_state():
    assert os.path.isfile(EXEC_PATH), f'Executable {EXEC_PATH} not found. Did you compile it?'
    mode = os.stat(EXEC_PATH).st_mode
    assert mode & stat.S_IXUSR, f'{EXEC_PATH} is not executable'
    with open(EXEC_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'mesh_sim must be a compiled ELF executable'

    assert os.path.isfile(SOLVER_PATH), 'solver.c is missing'
    assert os.path.isfile(MAIN_PATH), 'main.c is missing'
    with open(MAIN_PATH, 'r', newline='') as f:
        assert f.read() == TRUSTED_MAIN, 'main.c was modified; optimize only solver.c'

    # The submitted executable itself must run quickly and freshly generate output.
    run_and_check(EXEC_PATH)

    # Exercise solve_system directly on additional derived SPD, strictly diagonally
    # dominant systems rather than trusting a precomputed answer file.
    shared = '/tmp/submitted_solver.so'
    compile_shared = subprocess.run(
        ['gcc', '-O2', '-shared', '-fPIC', SOLVER_PATH, '-o', shared, '-lm'],
        capture_output=True, text=True
    )
    assert compile_shared.returncode == 0, (
        'solver.c could not be compiled independently:\n' + compile_shared.stderr
    )
    lib = ctypes.CDLL(shared)
    solve = lib.solve_system
    solve.argtypes = [
        ctypes.c_int,
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=2, flags='C_CONTIGUOUS'),
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags='C_CONTIGUOUS'),
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags='C_CONTIGUOUS'),
    ]
    solve.restype = None

    rng = np.random.default_rng(20260912)
    for n in (9, 23, 64):
        off = rng.uniform(-0.04, 0.04, size=(n, n))
        A = np.triu(off, 1)
        A = A + A.T
        A[np.diag_indices(n)] = np.sum(np.abs(A), axis=1) + rng.uniform(1.0, 2.0, n)
        b = rng.normal(size=n)
        expected = np.linalg.solve(A, b)
        work_A = np.ascontiguousarray(A.copy(), dtype=np.float64)
        work_b = np.ascontiguousarray(b.copy(), dtype=np.float64)
        actual = np.empty(n, dtype=np.float64)
        solve(n, work_A, work_b, actual)
        assert np.all(np.isfinite(actual)), 'solver produced non-finite values'
        assert np.allclose(actual, expected, rtol=1e-7, atol=1e-8), (
            f'solver.c returned an incorrect solution for a derived {n}x{n} SPD system'
        )

    # Rebuild from the unchanged trusted main and submitted solver, then repeat the
    # original runtime and accuracy assertions so a decoy mesh_sim cannot pass.
    trusted_main_path = '/tmp/trusted_main.c'
    trusted_exec = '/tmp/trusted_mesh_sim'
    with open(trusted_main_path, 'w', newline='') as f:
        f.write(TRUSTED_MAIN)
    compile_result = subprocess.run(
        ['gcc', '-O0', '-o', trusted_exec, trusted_main_path, SOLVER_PATH, '-lm'],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, (
        'Failed to build trusted main with submitted solver.c:\n' + compile_result.stderr
    )
    run_and_check(trusted_exec)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
