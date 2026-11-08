#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import pytest

HOME = "/home/user"
Y_NUMBER = r"-?(?:\d+\.\d{4})"


def read_matrix(path):
    with open(path) as f:
        return [[float(v) for v in line.strip().split(',')]
                for line in f if line.strip()]


def expected_results(x_path, w_path):
    x = read_matrix(x_path)
    w = read_matrix(w_path)
    assert len(x) == 100 and all(len(row) == 10 for row in x)
    assert len(w) == 10 and all(len(row) == 3 for row in w)
    y = [[sum(x[i][k] * w[k][j] for k in range(10)) for j in range(3)]
         for i in range(100)]
    values = [row[0] for row in y]
    mean = sum(values) / len(values)
    std = math.sqrt(sum((v - mean) ** 2 for v in values) / (len(values) - 1))
    margin = 1.96 * std / math.sqrt(len(values))
    return y, mean - margin, mean + margin


def assert_outputs(y_path, ci_path, x_path, w_path):
    expected_y, expected_lower, expected_upper = expected_results(x_path, w_path)

    with open(y_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_y), f"Y.csv row count ({len(lines)}) does not match expected ({len(expected_y)})."

    row_pattern = re.compile(rf"{Y_NUMBER},{Y_NUMBER},{Y_NUMBER}")
    for i, (line, expected_row) in enumerate(zip(lines, expected_y)):
        assert row_pattern.fullmatch(line), f"Y.csv row {i} is not three comma-separated values with exactly 4 decimal places: {line!r}"
        values = [float(v) for v in line.split(',')]
        assert len(values) == len(expected_row), f"Y.csv column count mismatch at row {i}."
        for j, (value, expected) in enumerate(zip(values, expected_row)):
            assert abs(value - expected) < 1e-3, f"Value mismatch at row {i}, col {j}: {value} != {expected}"

    with open(ci_path) as f:
        content = f.read().strip()
    match = re.fullmatch(rf"Lower: ({Y_NUMBER}), Upper: ({Y_NUMBER})", content)
    assert match, f"ci.txt format is incorrect. Expected 'Lower: [val], Upper: [val]', got: {content!r}"
    lower, upper = map(float, match.groups())
    assert abs(lower - expected_lower) < 1e-3, f"Lower bound mismatch: {lower} != {expected_lower}"
    assert abs(upper - expected_upper) < 1e-3, f"Upper bound mismatch: {upper} != {expected_upper}"


@pytest.fixture(scope="session")
def completed_pipeline():
    process_c = os.path.join(HOME, "process.c")
    pipeline = os.path.join(HOME, "pipeline.sh")
    assert os.path.isfile(process_c), "/home/user/process.c is missing"
    assert os.path.isfile(pipeline), "/home/user/pipeline.sh is missing"

    for path in (os.path.join(HOME, "Y.csv"), os.path.join(HOME, "ci.txt"), os.path.join(HOME, "process")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(["bash", pipeline], cwd=HOME, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=300)
    assert result.returncode == 0, "pipeline.sh failed:\n" + result.stdout
    assert os.path.isfile(os.path.join(HOME, "Y.csv")), "/home/user/Y.csv is missing after executing pipeline.sh"
    assert os.path.isfile(os.path.join(HOME, "ci.txt")), "/home/user/ci.txt is missing after executing pipeline.sh"
    assert os.path.isfile(os.path.join(HOME, "process")), "/home/user/process was not compiled by pipeline.sh"

    shutil.copyfile(os.path.join(HOME, "Y.csv"), "/tmp/original_Y.csv")
    shutil.copyfile(os.path.join(HOME, "ci.txt"), "/tmp/original_ci.txt")
    return result.stdout


def test_pipeline_files_exist(completed_pipeline):
    assert os.path.isfile(os.path.join(HOME, "process.c"))
    assert os.path.isfile(os.path.join(HOME, "pipeline.sh"))


def test_output_files_exist(completed_pipeline):
    assert os.path.isfile("/tmp/original_Y.csv")
    assert os.path.isfile("/tmp/original_ci.txt")


def test_original_output_content(completed_pipeline):
    assert_outputs("/tmp/original_Y.csv", "/tmp/original_ci.txt",
                   os.path.join(HOME, "X.csv"), os.path.join(HOME, "W.csv"))


def test_compiled_c_openblas_artifact(completed_pipeline):
    executable = os.path.join(HOME, "process")
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not an ELF executable"
    assert os.access(executable, os.X_OK), "/home/user/process is not executable"
    with open(os.path.join(HOME, "process.c"), errors="replace") as f:
        source = f.read()
    assert re.search(r"\bcblas_dgemm\s*\(", source), "process.c does not call cblas_dgemm"
    symbols = subprocess.run(["nm", "-D", executable], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    assert "cblas_dgemm" in symbols, "compiled process does not reference cblas_dgemm"


def test_process_on_unseen_inputs_and_dgemm_call(completed_pipeline):
    x_path = os.path.join(HOME, "X.csv")
    w_path = os.path.join(HOME, "W.csv")
    x_backup = "/tmp/X.csv.backup"
    w_backup = "/tmp/W.csv.backup"
    shutil.copyfile(x_path, x_backup)
    shutil.copyfile(w_path, w_backup)

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    x = [[rng.uniform(-3.0, 3.0) for _ in range(10)] for _ in range(100)]
    w = [[rng.uniform(-2.0, 2.0) for _ in range(3)] for _ in range(10)]

    wrapper_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
typedef void (*dgemm_fn)(int,int,int,int,int,int,double,const double*,int,const double*,int,double,double*,int);
void cblas_dgemm(int layout, int ta, int tb, int m, int n, int k,
                 double alpha, const double *a, int lda, const double *b, int ldb,
                 double beta, double *c, int ldc) {
    const char *marker = getenv("BLAS_MARKER");
    if (marker) { FILE *f = fopen(marker, "a"); if (f) { fputs("called\n", f); fclose(f); } }
    dgemm_fn real_fn = (dgemm_fn)dlsym(RTLD_NEXT, "cblas_dgemm");
    if (!real_fn) { fputs("unable to resolve cblas_dgemm\n", stderr); exit(97); }
    real_fn(layout, ta, tb, m, n, k, alpha, a, lda, b, ldb, beta, c, ldc);
}
'''
    try:
        with open(x_path, "w") as f:
            for row in x:
                f.write(",".join(format(v, ".17g") for v in row) + "\n")
        with open(w_path, "w") as f:
            for row in w:
                f.write(",".join(format(v, ".17g") for v in row) + "\n")

        with open("/tmp/dgemm_probe.c", "w") as f:
            f.write(wrapper_source)
        subprocess.run(["gcc", "-shared", "-fPIC", "/tmp/dgemm_probe.c", "-o",
                        "/tmp/dgemm_probe.so", "-ldl"], check=True)
        marker = "/tmp/dgemm_called"
        if os.path.exists(marker):
            os.remove(marker)
        for path in (os.path.join(HOME, "Y.csv"), os.path.join(HOME, "ci.txt")):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/dgemm_probe.so"
        env["BLAS_MARKER"] = marker
        result = subprocess.run([os.path.join(HOME, "process")], cwd=HOME, env=env,
                                text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        assert result.returncode == 0, "compiled process failed on unseen inputs:\n" + result.stdout
        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "process did not call cblas_dgemm"
        assert_outputs(os.path.join(HOME, "Y.csv"), os.path.join(HOME, "ci.txt"), x_path, w_path)
    finally:
        shutil.copyfile(x_backup, x_path)
        shutil.copyfile(w_backup, w_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
