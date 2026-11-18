#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /app/eval/clean /app/eval/evil /home/user/samples

    # Create the oracle in C
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 2;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 2;
    char line[1024];
    double x[10000], y[10000];
    int n = 0;
    while (fgets(line, sizeof(line), f) && n < 10000) {
        double c0, c1, c2, c3, c4;
        if (sscanf(line, "%lf,%lf,%lf,%lf,%lf", &c0, &c1, &c2, &c3, &c4) == 5) {
            x[n] = c1;
            y[n] = c3;
            n++;
        }
    }
    fclose(f);
    if (n == 0) return 0;
    double sum_x = 0, sum_y = 0;
    for (int i=0; i<n; i++) { sum_x += x[i]; sum_y += y[i]; }
    double mean_x = sum_x / n;
    double mean_y = sum_y / n;
    double num = 0, den_x = 0, den_y = 0;
    for (int i=0; i<n; i++) {
        double dx = x[i] - mean_x;
        double dy = y[i] - mean_y;
        num += dx * dy;
        den_x += dx * dx;
        den_y += dy * dy;
    }
    double r = num / sqrt(den_x * den_y);
    if (fabs(r) > 0.85) return 1;
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/detector_oracle -lm
    strip /app/detector_oracle
    rm /tmp/oracle.c

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import os
import random

def generate_csv(path, n_rows, is_evil):
    with open(path, 'w') as f:
        for _ in range(n_rows):
            c0 = random.gauss(0, 1)
            c1 = random.gauss(0, 1)
            c2 = random.gauss(0, 1)
            if is_evil:
                c3 = 0.9 * c1 + 0.1 * random.gauss(0, 1)
            else:
                c3 = random.gauss(0, 1)
            c4 = random.gauss(0, 1)
            f.write(f"{c0},{c1},{c2},{c3},{c4}\n")

for i in range(50):
    generate_csv(f'/app/eval/clean/clean_{i}.csv', 100, False)
    generate_csv(f'/app/eval/evil/evil_{i}.csv', 100, True)

for i in range(5):
    generate_csv(f'/home/user/samples/clean_{i}.csv', 100, False)
    generate_csv(f'/home/user/samples/evil_{i}.csv', 100, True)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
