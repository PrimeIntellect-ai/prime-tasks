#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils python3-numpy python3-scipy
    pip3 install pytest

    mkdir -p /home/user/data/clean /home/user/data/evil /app

    cat << 'EOF' > /tmp/fitter.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    double t, y;
    double sum_y = 0;
    int count = 0;
    while (fscanf(f, "%lf,%lf", &t, &y) == 2) {
        sum_y += y;
        count++;
    }
    fclose(f);

    if (sum_y / count > 50.0) {
        printf("ERROR: NaN\n");
        return 255;
    }
    printf("FIT_SUCCESS: %f\n", sum_y);
    return 0;
}
EOF
    gcc -O2 /tmp/fitter.c -o /app/kinetics_fitter
    strip /app/kinetics_fitter
    chmod +x /app/kinetics_fitter

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

np.random.seed(42)
os.makedirs('/home/user/data/clean', exist_ok=True)
os.makedirs('/home/user/data/evil', exist_ok=True)

# Clean: Decay data
for i in range(10):
    t = np.linspace(0, 10, 100)
    A, B, C = np.random.uniform(5, 10), np.random.uniform(0.5, 1.5), np.random.uniform(0, 2)
    y = A * np.exp(-B * t) + C + np.random.normal(0, 0.1, 100)
    np.savetxt(f'/home/user/data/clean/dataset_{i}.csv', np.column_stack((t,y)), delimiter=',')

# Evil: Growth data
for i in range(10):
    t = np.linspace(0, 10, 100)
    A, B, C = np.random.uniform(5, 10), np.random.uniform(-0.5, -0.1), np.random.uniform(0, 2)
    y = A * np.exp(-B * t) + C + np.random.normal(0, 0.1, 100)
    np.savetxt(f'/home/user/data/evil/dataset_{i}.csv', np.column_stack((t,y)), delimiter=',')
EOF
    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
