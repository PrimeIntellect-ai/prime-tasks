#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy

    mkdir -p /app/sample_data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/preprocess.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 3) return 1;
    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) return 1;

    char line[1024];
    if (!fgets(line, sizeof(line), in)) return 1;
    fprintf(out, "%s", line);

    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0, sum_y2 = 0;
    int n = 0;

    while (fgets(line, sizeof(line), in)) {
        double x, y, z;
        if (sscanf(line, "%lf,%lf,%lf", &x, &y, &z) == 3) {
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_x2 += x * x;
            sum_y2 += y * y;
            n++;
        }
    }

    if (n == 0) return 1;

    double mean_x = sum_x / n;
    double mean_y = sum_y / n;
    double cov_xy = (sum_xy / n) - (mean_x * mean_y);
    double var_x = (sum_x2 / n) - (mean_x * mean_x);
    double var_y = (sum_y2 / n) - (mean_y * mean_y);

    double r = cov_xy / sqrt(var_x * var_y);

    rewind(in);
    fgets(line, sizeof(line), in); // skip header

    while (fgets(line, sizeof(line), in)) {
        double x, y, z;
        if (sscanf(line, "%lf,%lf,%lf", &x, &y, &z) == 3) {
            if (fabs(r) > 0.99) {
                fprintf(out, "NaN,NaN,NaN\n");
            } else {
                fprintf(out, "%f,%f,%f\n", x + 1.0, y + 1.0, z + 1.0);
            }
        }
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    gcc -O2 /tmp/preprocess.c -o /app/preprocess_bin -lm
    strip /app/preprocess_bin
    rm /tmp/preprocess.c

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

def make_csv(path, r, n=100):
    cov = [[1.0, r], [r, 1.0]]
    xy = np.random.multivariate_normal([0, 0], cov, n)
    z = np.random.randn(n)
    with open(path, 'w') as f:
        f.write("X,Y,Z\n")
        for i in range(n):
            f.write(f"{xy[i,0]},{xy[i,1]},{z[i]}\n")

rs = [0.5, 0.95, 0.98, -0.5, -0.95, -0.98, 0.991, 0.995, 0.999, -0.991, -0.995, -0.999]
for i, r in enumerate(rs):
    make_csv(f'/app/sample_data/sample_{i}.csv', r)

for i in range(50):
    r = np.random.uniform(-0.98, 0.98)
    make_csv(f'/app/corpus/clean/clean_{i}.csv', r)

for i in range(50):
    r = np.random.uniform(0.9901, 0.9999)
    if np.random.rand() > 0.5: r = -r
    make_csv(f'/app/corpus/evil/evil_{i}.csv', r)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
