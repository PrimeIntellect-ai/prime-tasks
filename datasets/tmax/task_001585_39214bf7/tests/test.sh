#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import shutil
import subprocess

SOURCE = '/home/user/validate_pca.c'
EXECUTABLE = '/home/user/validate_pca'
FRESH_EXECUTABLE = '/tmp/validate_pca_fresh'


def read_matrix(path):
    """Reads a space-separated text file into a 2D list of floats."""
    with open(path, 'r') as f:
        return [[float(x) for x in line.split()] for line in f if line.strip()]


def expected_max_diff():
    X = read_matrix('/home/user/X.txt')
    P = read_matrix('/home/user/P.txt')
    Y_ref = read_matrix('/home/user/Y_ref.txt')
    Y_computed = []
    for i in range(len(X)):
        row = []
        for j in range(len(P[0])):
            row.append(sum(X[i][k] * P[k][j] for k in range(len(X[0]))))
        Y_computed.append(row)

    max_diff = 0.0
    for i in range(len(Y_ref)):
        for j in range(len(Y_ref[0])):
            max_diff = max(max_diff, abs(Y_computed[i][j] - Y_ref[i][j]))
    return max_diff


def read_output():
    with open('/home/user/max_diff.txt', 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', content), \
        f"max_diff.txt must contain only one floating-point value, got: {content!r}"
    return float(content)


def run_program(path, env=None):
    result = subprocess.run([path], cwd='/home/user', env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=20)
    assert result.returncode == 0, \
        f"{path} failed with status {result.returncode}: {result.stderr}"
    assert os.path.isfile('/home/user/max_diff.txt'), \
        f"{path} did not create /home/user/max_diff.txt"
    return read_output()


def write_matrix(path, matrix):
    with open(path, 'w') as f:
        for row in matrix:
            f.write(' '.join(f'{value:.6f}' for value in row) + '\n')


def install_challenge_inputs():
    X = [[(((i + 3) * (k + 5) * 17) % 211 - 105) / 37.0
          for k in range(10)] for i in range(100)]
    P = [[(((k + 7) * (j + 11) * 13) % 97 - 48) / 29.0
          for j in range(3)] for k in range(10)]
    # Round inputs exactly as the task files are rounded, then derive Y_ref.
    X = [[float(f'{v:.6f}') for v in row] for row in X]
    P = [[float(f'{v:.6f}') for v in row] for row in P]
    Y = [[sum(X[i][k] * P[k][j] for k in range(10)) for j in range(3)]
         for i in range(100)]
    Y_ref = [[Y[i][j] + (((i * 3 + j) % 9) - 4) * 0.000007
              for j in range(3)] for i in range(100)]
    write_matrix('/home/user/X.txt', X)
    write_matrix('/home/user/P.txt', P)
    write_matrix('/home/user/Y_ref.txt', Y_ref)


def test_openblas_installed():
    """Test that OpenBLAS headers and library are installed."""
    header_found = False
    for root, dirs, files in os.walk('/usr/include'):
        if 'cblas.h' in files:
            header_found = True
            break
    assert header_found, "cblas.h not found in /usr/include. OpenBLAS development headers may not be installed."

    libraries = subprocess.run(['ldconfig', '-p'], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, check=True).stdout
    assert re.search(r'libopenblas[^ ]*\.so', libraries), \
        "The OpenBLAS shared library is not installed or registered."


def test_c_source_exists():
    """Test that the C source code exists."""
    assert os.path.isfile(SOURCE), "Source file /home/user/validate_pca.c is missing."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_max_diff_correct():
    """Test that max_diff.txt contains the correctly computed maximum absolute difference."""
    diff_file = '/home/user/max_diff.txt'
    assert os.path.isfile(diff_file), f"Output file {diff_file} is missing."
    max_diff = expected_max_diff()
    with open(diff_file, 'r') as f:
        content = f.read().strip()
    try:
        student_diff = float(content)
    except ValueError:
        assert False, f"Contents of {diff_file} could not be parsed as a float: '{content}'"
    assert math.isclose(student_diff, max_diff, abs_tol=1.5e-5), \
        f"Expected max difference around {max_diff:.6f}, but got {student_diff}"


def test_source_builds_and_artifacts_use_openblas():
    """Compile the submitted source and verify both binaries really reference OpenBLAS DGEMM."""
    build = subprocess.run(
        ['gcc', '-std=c11', '-Wall', '-Wextra', SOURCE, '-o', FRESH_EXECUTABLE,
         '-lopenblas', '-lm'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert build.returncode == 0, f"Submitted C source does not compile with OpenBLAS: {build.stderr}"

    for path in (EXECUTABLE, FRESH_EXECUTABLE):
        file_info = subprocess.run(['file', path], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, check=True).stdout
        assert 'ELF' in file_info, f"{path} is not a compiled ELF executable"
        linked = subprocess.run(['ldd', path], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, check=True).stdout.lower()
        assert 'openblas' in linked, f"{path} is not dynamically linked to OpenBLAS"
        symbols = subprocess.run(['nm', '-D', path], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, check=True).stdout
        assert re.search(r'\b[UuWw]\s+cblas_dgemm(?:@|\s|$)', symbols, re.MULTILINE), \
            f"{path} does not reference cblas_dgemm"


def test_programs_run_on_derived_inputs_and_depend_on_dgemm():
    """Run both artifacts on challenge data and confirm the source uses DGEMM's result."""
    paths = ['/home/user/X.txt', '/home/user/P.txt', '/home/user/Y_ref.txt',
             '/home/user/max_diff.txt']
    backups = {}
    for path in paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    wrapper_source = r'''
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <cblas.h>

typedef void (*dgemm_fn)(const CBLAS_LAYOUT, const CBLAS_TRANSPOSE,
                         const CBLAS_TRANSPOSE, const CBLAS_INT,
                         const CBLAS_INT, const CBLAS_INT, const double,
                         const double *, const CBLAS_INT, const double *,
                         const CBLAS_INT, const double, double *,
                         const CBLAS_INT);

void cblas_dgemm(const CBLAS_LAYOUT layout, const CBLAS_TRANSPOSE transa,
                 const CBLAS_TRANSPOSE transb, const CBLAS_INT m,
                 const CBLAS_INT n, const CBLAS_INT k, const double alpha,
                 const double *a, const CBLAS_INT lda, const double *b,
                 const CBLAS_INT ldb, const double beta, double *c,
                 const CBLAS_INT ldc) {
    dgemm_fn real_fn = (dgemm_fn)dlsym(RTLD_NEXT, "cblas_dgemm");
    if (!real_fn) _Exit(90);
    FILE *log = fopen("/tmp/cblas_called", "a");
    if (log) { fprintf(log, "%d %d %d\n", (int)m, (int)n, (int)k); fclose(log); }
    real_fn(layout, transa, transb, m, n, k, alpha, a, lda, b, ldb, beta, c, ldc);
    if (c && m > 0 && n > 0) c[0] += 12345.0;
}
'''
    try:
        install_challenge_inputs()
        expected = expected_max_diff()

        fresh_result = run_program(FRESH_EXECUTABLE)
        assert math.isclose(fresh_result, expected, abs_tol=1.5e-6), \
            f"Freshly compiled source returned {fresh_result}, expected {expected:.6f}"

        submitted_result = run_program(EXECUTABLE)
        assert math.isclose(submitted_result, expected, abs_tol=1.5e-6), \
            f"Submitted executable returned {submitted_result}, expected {expected:.6f}"

        with open('/tmp/cblas_probe.c', 'w') as f:
            f.write(wrapper_source)
        probe_build = subprocess.run(
            ['gcc', '-shared', '-fPIC', '/tmp/cblas_probe.c', '-o',
             '/tmp/cblas_probe.so', '-ldl'], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30)
        assert probe_build.returncode == 0, \
            f"Could not build the DGEMM verification probe: {probe_build.stderr}"
        if os.path.exists('/tmp/cblas_called'):
            os.unlink('/tmp/cblas_called')
        env = os.environ.copy()
        env['LD_PRELOAD'] = '/tmp/cblas_probe.so'
        probed_result = run_program(FRESH_EXECUTABLE, env=env)
        assert os.path.isfile('/tmp/cblas_called'), "The program did not call cblas_dgemm"
        with open('/tmp/cblas_called') as f:
            calls = [line.strip() for line in f if line.strip()]
        assert '100 3 10' in calls, \
            f"cblas_dgemm was not called for the required 100x10 by 10x3 multiplication: {calls}"
        assert abs(probed_result - expected) > 1000.0, \
            "Changing cblas_dgemm's output did not affect the reported error; the program is not using its result"
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, 'wb') as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
