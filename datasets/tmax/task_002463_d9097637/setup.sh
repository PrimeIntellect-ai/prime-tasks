#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import subprocess
import numpy as np

def setup():
    os.makedirs("/home/user", exist_ok=True)

    # Generate data.txt
    np.random.seed(123)
    large = np.random.uniform(1e6, 1e7, 100)
    small = np.random.uniform(-1, 1, 99900)
    data = np.concatenate([large, small])
    np.random.shuffle(data)

    with open("/home/user/data.txt", "w") as f:
        for x in data:
            f.write(f"{x}\n")

    # Generate expected output to verify truth
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

    FILE *out = fopen("/home/user/expected_ci.txt", "w");
    fprintf(out, "[%f, %f]\\n", diffs[24], diffs[974]);
    fclose(out);
    return 0;
}
"""
    with open("/tmp/truth_sum.c", "w") as f:
        f.write(c_code)

    subprocess.run(["gcc", "-O3", "/tmp/truth_sum.c", "-o", "/tmp/truth_sum", "-lm"], check=True)
    subprocess.run(["/tmp/truth_sum", "/home/user/data.txt"], check=True)

setup()
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
