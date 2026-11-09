#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_c_file_exists():
    assert os.path.isfile("/home/user/bootstrap_sum.c"), "/home/user/bootstrap_sum.c is missing."

def test_bash_script_exists():
    assert os.path.isfile("/home/user/run_analysis.sh"), "/home/user/run_analysis.sh is missing."

def test_output_matches():
    assert os.path.isfile("/home/user/ci_output.txt"), "/home/user/ci_output.txt is missing."

    # Recompute expected output to avoid hardcoding opaque constants and ensure exact float semantics
    c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

unsigned int my_seed = 42;
unsigned int my_rand() {
    my_seed = my_seed * 1664525 + 1013904223;
    return my_seed;
}

int compare(const void *a, const void *b) {
    float fa = fabsf(*(const float*)a);
    float fb = fabsf(*(const float*)b);
    return (fa > fb) - (fa < fb);
}

int cmp_diff(const void *a, const void *b) {
    float fa = *(const float*)a;
    float fb = *(const float*)b;
    return (fa > fb) - (fa < fb);
}

int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    int N = 100000;
    float *data = malloc(N * sizeof(float));
    for (int i = 0; i < N; i++) {
        fscanf(f, "%f", &data[i]);
    }
    fclose(f);

    my_seed = 42;
    int B = 1000;
    float *diffs = malloc(B * sizeof(float));
    float *resamp = malloc(N * sizeof(float));

    for (int b = 0; b < B; b++) {
        for (int i = 0; i < N; i++) {
            resamp[i] = data[my_rand() % N];
        }
        float sumA = 0;
        for (int i = 0; i < N; i++) sumA += resamp[i];

        qsort(resamp, N, sizeof(float), compare);

        float sumB = 0;
        for (int i = 0; i < N; i++) sumB += resamp[i];

        diffs[b] = (sumA / N) - (sumB / N);
    }

    qsort(diffs, B, sizeof(float), cmp_diff);

    printf("[%f, %f]", diffs[24], diffs[974]);
    return 0;
}
"""
    test_c_path = "/tmp/test_truth_sum.c"
    test_bin_path = "/tmp/test_truth_sum"

    with open(test_c_path, "w") as f:
        f.write(c_code)

    subprocess.run(["gcc", "-O3", test_c_path, "-o", test_bin_path, "-lm"], check=True)
    res = subprocess.run([test_bin_path, "/home/user/data.txt"], capture_output=True, text=True, check=True)
    expected_out = res.stdout.strip()

    with open("/home/user/ci_output.txt", "r") as f:
        actual_out = f.read().strip()

    assert actual_out == expected_out, f"Output mismatch. Expected '{expected_out}', but got '{actual_out}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
