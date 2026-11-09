#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/sim_data/process_svd.c"
MATRIX = "/home/user/sim_data/matrix.txt"
RESULT = "/home/user/sim_data/result.txt"
BINARY = "/tmp/process_svd_submission"
MARKER = "/tmp/gsl_svd_called"
PRELOAD = "/tmp/gsl_svd_probe.so"


def test_c_program_exists():
    """Test that the C program process_svd.c exists."""
    file_path = "/home/user/sim_data/process_svd.c"
    assert os.path.isfile(file_path), f"The C program file {file_path} does not exist."


def test_result_file_exists():
    """Test that the result.txt file exists."""
    file_path = "/home/user/sim_data/result.txt"
    assert os.path.isfile(file_path), f"The result file {file_path} does not exist. Did you run the compiled program?"


def test_result_file_content():
    """Test that the result.txt file contains the correct largest singular value."""
    file_path = "/home/user/sim_data/result.txt"
    assert os.path.isfile(file_path), f"The result file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_value = "25.4624"
    assert content == expected_value, f"The content of {file_path} is '{content}', expected '{expected_value}'."


def largest_singular_value(matrix):
    # Independently compute the eigenvalues of A^T A with Jacobi rotations.
    gram = [[sum(row[i] * row[j] for row in matrix) for j in range(3)] for i in range(3)]
    for _ in range(100):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda pair: abs(gram[pair[0]][pair[1]]))
        if abs(gram[p][q]) < 1e-13:
            break
        app, aqq, apq = gram[p][p], gram[q][q], gram[p][q]
        theta = 0.5 * math.atan2(2.0 * apq, aqq - app)
        c, s = math.cos(theta), math.sin(theta)
        for k in range(3):
            if k not in (p, q):
                akp, akq = gram[k][p], gram[k][q]
                gram[k][p] = gram[p][k] = c * akp - s * akq
                gram[k][q] = gram[q][k] = s * akp + c * akq
        gram[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        gram[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        gram[p][q] = gram[q][p] = 0.0
    return math.sqrt(max(0.0, max(gram[i][i] for i in range(3))))


def write_matrix(matrix):
    with open(MATRIX, "w") as f:
        for row in matrix:
            f.write(" ".join(format(value, ".17g") for value in row) + "\n")


def build_probe():
    probe_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_linalg.h>

static void mark_call(void) {
    FILE *f = fopen("/tmp/gsl_svd_called", "a");
    if (f) { fputc('1', f); fclose(f); }
}

int gsl_linalg_SV_decomp(gsl_matrix *A, gsl_matrix *V, gsl_vector *S, gsl_vector *work) {
    typedef int (*fn_t)(gsl_matrix *, gsl_matrix *, gsl_vector *, gsl_vector *);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp");
    mark_call();
    return real_fn(A, V, S, work);
}

int gsl_linalg_SV_decomp_mod(gsl_matrix *A, gsl_matrix *X, gsl_matrix *V, gsl_vector *S, gsl_vector *work) {
    typedef int (*fn_t)(gsl_matrix *, gsl_matrix *, gsl_matrix *, gsl_vector *, gsl_vector *);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp_mod");
    mark_call();
    return real_fn(A, X, V, S, work);
}

int gsl_linalg_SV_decomp_jacobi(gsl_matrix *A, gsl_matrix *V, gsl_vector *S) {
    typedef int (*fn_t)(gsl_matrix *, gsl_matrix *, gsl_vector *);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp_jacobi");
    mark_call();
    return real_fn(A, V, S);
}
'''
    with open("/tmp/gsl_svd_probe.c", "w") as f:
        f.write(probe_source)
    proc = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/gsl_svd_probe.c", "-o", PRELOAD, "-ldl"],
        text=True, capture_output=True
    )
    assert proc.returncode == 0, f"Could not build verification probe:\n{proc.stderr}"


def test_program_compiles_uses_gsl_and_processes_matrix():
    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    assert re.search(r'#\s*include\s*[<\"]gsl/', source_text), "The program must include and use GSL headers."

    compile_proc = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lgsl", "-lgslcblas", "-lm"],
        text=True, capture_output=True
    )
    assert compile_proc.returncode == 0, f"process_svd.c did not compile with the required GSL libraries:\n{compile_proc.stderr}"

    symbols = subprocess.run(["nm", "-D", BINARY], text=True, capture_output=True, check=True).stdout
    assert re.search(r'\bU\s+gsl_linalg_SV_decomp(?:_mod|_jacobi)?(?:@|$)', symbols, re.MULTILINE), \
        "The compiled program does not call a GSL SVD routine."

    build_probe()
    original_matrix = open(MATRIX, "rb").read()
    original_result = open(RESULT, "rb").read() if os.path.isfile(RESULT) else None
    cases = [
        [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0], [10.0, 11.0, 12.0]],
        [[3.25, -1.5, 2.0], [0.75, 4.5, -3.0], [-2.25, 1.0, 5.5], [6.0, -0.5, 1.25]],
        [[-7.0, 2.5, 0.25], [1.5, -3.75, 4.0], [2.0, 8.25, -1.0], [-0.5, 3.0, 6.75]],
    ]

    try:
        for matrix in cases:
            write_matrix(matrix)
            if os.path.exists(RESULT):
                os.unlink(RESULT)
            if os.path.exists(MARKER):
                os.unlink(MARKER)

            env = os.environ.copy()
            env["LD_PRELOAD"] = PRELOAD
            run_proc = subprocess.run([BINARY], cwd="/home/user/sim_data", env=env,
                                      text=True, capture_output=True, timeout=10)
            assert run_proc.returncode == 0, f"The compiled program failed:\n{run_proc.stderr}"
            assert os.path.isfile(RESULT), "The compiled program did not create result.txt."
            assert os.path.isfile(MARKER) and os.path.getsize(MARKER) > 0, \
                "The program did not invoke a GSL SVD routine while processing the matrix."

            with open(RESULT, "r") as f:
                actual = f.read().strip()
            expected = f"{largest_singular_value(matrix):.4f}"
            assert re.fullmatch(r'[+-]?\d+\.\d{4}', actual), \
                f"result.txt must contain one number with exactly four decimal places, got {actual!r}."
            assert actual == expected, f"For the supplied matrix, result.txt contained {actual!r}, expected {expected!r}."
    finally:
        with open(MATRIX, "wb") as f:
            f.write(original_matrix)
        if original_result is None:
            if os.path.exists(RESULT):
                os.unlink(RESULT)
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
