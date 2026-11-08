#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SOURCE = "/home/user/compare_spectra.c"
SPECTRUM = "/home/user/spectrum.txt"
RESULT = "/home/user/result.txt"
EXECUTABLE = "/tmp/candidate_compare_spectra"

REFERENCE_CODE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int compare_doubles(const void *a, const void *b) {
    double arg1 = *(const double *)a;
    double arg2 = *(const double *)b;
    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

int main(void) {
    double data[1000];
    FILE *f = fopen("/home/user/spectrum.txt", "r");
    if (!f) return 1;
    for (int i = 0; i < 1000; i++) {
        if (fscanf(f, "%lf", &data[i]) != 1) return 1;
    }
    fclose(f);

    double Q[1000];
    double sum_Q = 0.0;
    for (int i = 0; i < 1000; i++) {
        Q[i] = exp(-i / 200.0);
        sum_Q += Q[i];
    }
    for (int i = 0; i < 1000; i++) Q[i] /= sum_Q;

    srand(42);
    double tvds[100];
    for (int b = 0; b < 100; b++) {
        double P[1000];
        double sum_P = 0.0;
        for (int i = 0; i < 1000; i++) {
            int idx = rand() % 1000;
            P[i] = data[idx];
            sum_P += P[i];
        }
        for (int i = 0; i < 1000; i++) P[i] /= sum_P;

        double tvd = 0.0;
        for (int i = 0; i < 1000; i++) {
            tvd += fabs(P[i] - Q[i]);
        }
        tvds[b] = tvd / 2.0;
    }

    qsort(tvds, 100, sizeof(double), compare_doubles);

    FILE *out = fopen("/tmp/expected_result.txt", "w");
    if (!out) return 1;
    fprintf(out, "CI: [%f, %f]\n", tvds[4], tvds[94]);
    fclose(out);
    return 0;
}
'''

def get_expected_result():
    with open("/tmp/ref_compare.c", "w") as f:
        f.write(REFERENCE_CODE)
    subprocess.run(
        ["gcc", "-O3", "/tmp/ref_compare.c", "-lm", "-o", "/tmp/ref_compare"],
        check=True,
        timeout=30,
    )
    subprocess.run(["/tmp/ref_compare"], check=True, timeout=30)
    with open("/tmp/expected_result.txt", "r") as f:
        return f.read().strip()

def read_actual_result():
    assert os.path.isfile(RESULT), "/home/user/result.txt does not exist."
    with open(RESULT, "r") as f:
        return f.read().strip()

def compile_candidate():
    subprocess.run(
        ["gcc", "-O3", SOURCE, "-lm", "-o", EXECUTABLE],
        check=True,
        timeout=30,
    )

def run_candidate():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    subprocess.run([EXECUTABLE], check=True, timeout=30)
    assert os.path.isfile(RESULT), "Compiled program did not create /home/user/result.txt."

def test_compare_spectra_c_exists():
    assert os.path.isfile(SOURCE), "/home/user/compare_spectra.c does not exist."

def test_result_txt_exists():
    assert os.path.isfile(RESULT), "/home/user/result.txt does not exist."

def test_result_txt_content():
    expected_str = get_expected_result()
    actual_str = read_actual_result()
    assert actual_str == expected_str, (
        f"Contents of /home/user/result.txt do not match exactly. "
        f"Expected: '{expected_str}', Got: '{actual_str}'"
    )

def test_program_compiles_and_generates_original_result():
    expected_str = get_expected_result()
    compile_candidate()
    run_candidate()
    actual_str = read_actual_result()
    assert actual_str == expected_str, (
        f"Running compare_spectra.c produced '{actual_str}', expected '{expected_str}'"
    )

def test_program_handles_fresh_empirical_data():
    with open(SPECTRUM, "rb") as f:
        original_spectrum = f.read()
    original_result = None
    if os.path.exists(RESULT):
        with open(RESULT, "rb") as f:
            original_result = f.read()

    try:
        raw = secrets.token_bytes(2000)
        values = []
        for i in range(1000):
            n = (raw[2 * i] << 8) | raw[2 * i + 1]
            value = 0.01 + n / 4096.0 + ((i * 37) % 113) / 137.0
            values.append(value)
        with open(SPECTRUM, "w") as f:
            for value in values:
                f.write(f"{value:.12f}\n")

        expected_str = get_expected_result()
        run_candidate()
        actual_str = read_actual_result()
        assert actual_str == expected_str, (
            "The compiled program did not compute the required result for fresh "
            f"empirical data. Expected '{expected_str}', Got '{actual_str}'"
        )
    finally:
        with open(SPECTRUM, "wb") as f:
            f.write(original_spectrum)
        if original_result is None:
            if os.path.exists(RESULT):
                os.remove(RESULT)
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
