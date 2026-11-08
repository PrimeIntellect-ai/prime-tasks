#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/reference_data_gen.c
#include <stdio.h>
#include <math.h>

float compute_feature(int i, int j) {
    float dt = 0.001f;
    float y = (float)(i + j + 1);
    float sum = 0.0f;
    float c = 0.0f;
    for (int step = 0; step < 100000; step++) {
        float dy = -0.01f * y * dt;
        y += dy;
        float y_val = (y * dt) - c;
        float t = sum + y_val;
        c = (t - sum) - y_val;
        sum = t;
    }
    return sum;
}

int main(void) {
    FILE *f = fopen("/tmp/expected_matrix.txt", "w");
    if (!f) return 1;
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 10; j++) {
            fprintf(f, "%f ", compute_feature(i, j));
        }
        fprintf(f, "\n");
    }
    fclose(f);
    return 0;
}
REF_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ctypes
import math
import subprocess


def setup_module(module):
    source = "/home/user/data_gen.c"
    assert os.path.isfile(source), f"File {source} does not exist or is not a regular file."

    subprocess.run(
        ["gcc", "-std=c11", "-O0", "-fno-fast-math", "/tmp/reference_data_gen.c", "-lm", "-o", "/tmp/reference_data_gen"],
        check=True,
        timeout=30,
    )
    if os.path.exists("/tmp/expected_matrix.txt"):
        os.remove("/tmp/expected_matrix.txt")
    subprocess.run(["/tmp/reference_data_gen"], check=True, timeout=30)

    subprocess.run(
        ["gcc", "-std=c11", "-O0", "-fno-fast-math", source, "-lm", "-o", "/tmp/submitted_data_gen"],
        check=True,
        timeout=30,
    )
    if os.path.exists("/home/user/matrix.txt"):
        os.remove("/home/user/matrix.txt")
    subprocess.run(["/tmp/submitted_data_gen"], check=True, timeout=30)


def compute_expected_matrix():
    # Emulate 32-bit float Kahan summation
    def kahan_sum(k):
        dt = ctypes.c_float(0.001)
        y = ctypes.c_float(k)
        sum_val = ctypes.c_float(0.0)
        c = ctypes.c_float(0.0)

        for _ in range(100000):
            dy = ctypes.c_float(ctypes.c_float(-0.01).value * y.value * dt.value)
            y = ctypes.c_float(y.value + dy.value)
            y_dt = ctypes.c_float(y.value * dt.value)
            y_val = ctypes.c_float(y_dt.value - c.value)
            t = ctypes.c_float(sum_val.value + y_val.value)
            c = ctypes.c_float((t.value - sum_val.value) - y_val.value)
            sum_val = t

        return sum_val.value

    matrix = [[0.0] * 10 for _ in range(10)]
    for i in range(10):
        for j in range(10):
            matrix[i][j] = kahan_sum(i + j + 1)
    return matrix


def compute_largest_singular_value(matrix):
    # The matrix is symmetric and has positive entries, so the largest singular value
    # is the largest eigenvalue, which can be found via power iteration.
    v = [1.0] * 10
    for _ in range(1000):
        v_new = [sum(matrix[i][j] * v[j] for j in range(10)) for i in range(10)]
        norm = math.sqrt(sum(x * x for x in v_new))
        v = [x / norm for x in v_new]

    # Rayleigh quotient
    eigenvalue = sum(v[i] * sum(matrix[i][j] * v[j] for j in range(10)) for i in range(10))
    return eigenvalue


def read_matrix(path):
    with open(path, "r") as f:
        rows = [line.split() for line in f if line.strip()]
    assert len(rows) == 10, f"{path} must contain exactly 10 non-empty rows, found {len(rows)}."
    assert all(len(row) == 10 for row in rows), f"Each row of {path} must contain exactly 10 values."
    try:
        matrix = [[float(value) for value in row] for row in rows]
    except ValueError as exc:
        assert False, f"{path} contains a non-numeric matrix entry: {exc}"
    assert all(math.isfinite(value) for row in matrix for value in row), f"{path} contains a non-finite value."
    return matrix


def test_kahan_summation_implemented():
    file_path = "/home/user/data_gen.c"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    # Check that naive summation is removed and Kahan algorithm is present
    assert "sum += y * dt;" not in content, "Naive summation 'sum += y * dt;' is still in data_gen.c"
    assert "c =" in content or "c=" in content, "Kahan summation variable 'c' seems missing."
    assert "t =" in content or "t=" in content, "Kahan summation variable 't' seems missing."


def test_matrix_file_exists():
    assert os.path.exists("/home/user/matrix.txt"), "/home/user/matrix.txt was not created."

    actual = read_matrix("/home/user/matrix.txt")
    expected = read_matrix("/tmp/expected_matrix.txt")
    for i in range(10):
        for j in range(10):
            assert math.isclose(actual[i][j], expected[i][j], rel_tol=0.0, abs_tol=1e-5), \
                f"matrix.txt entry ({i}, {j}) is {actual[i][j]}, expected {expected[i][j]} from float Kahan integration."


def test_result_file_correct():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"File {result_path} does not exist."

    with open(result_path, "r") as f:
        result_str = f.read().strip()

    assert result_str, f"File {result_path} is empty."

    try:
        result_val = float(result_str)
    except ValueError:
        assert False, f"Content of {result_path} is not a valid float: '{result_str}'"

    # Check if formatted to 4 decimal places
    assert "." in result_str and len(result_str.split(".")[1]) == 4, f"Result '{result_str}' is not formatted to exactly 4 decimal places."

    expected_matrix = compute_expected_matrix()
    expected_sv = compute_largest_singular_value(expected_matrix)
    expected_sv_rounded = round(expected_sv, 4)

    assert math.isclose(result_val, expected_sv_rounded, abs_tol=0.0002), \
        f"Expected largest singular value approximately {expected_sv_rounded:.4f}, but got {result_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
