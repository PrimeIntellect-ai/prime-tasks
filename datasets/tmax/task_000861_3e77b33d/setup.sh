#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest numpy

mkdir -p /app/bin
mkdir -p /app/data/clean
mkdir -p /app/data/evil

# Create the sim_engine C code
cat << 'EOF' > /tmp/sim_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

double randn() {
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char** argv) {
    int steps = 1000;
    double dt = 0.01;
    char* out_path = "trajectory.csv";

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--steps") == 0 && i + 1 < argc) {
            steps = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--dt") == 0 && i + 1 < argc) {
            dt = atof(argv[++i]);
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        }
    }

    FILE* f = fopen(out_path, "w");
    if (!f) return 1;

    fprintf(f, "time,x\n");

    double x = 1.0;
    double v = 0.0;
    double k = 5.0;
    double gamma = 0.1;
    double sigma = 1.0;

    srand(time(NULL));

    for (int i = 0; i < steps; i++) {
        double t = i * dt;
        fprintf(f, "%f,%f\n", t, x);

        double dW = randn() * sqrt(dt);
        double dx = v * dt;
        double dv = (-k * x - gamma * v) * dt + sigma * dW;

        x += dx;
        v += dv;
    }

    fclose(f);
    return 0;
}
EOF

gcc -O2 -s /tmp/sim_engine.c -o /app/bin/sim_engine -lm

# Generate clean and evil data using Python
cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

np.random.seed(42)

def generate_clean(filename):
    dt = 0.01
    steps = 1000
    t = np.arange(steps) * dt
    # Simple damped harmonic oscillator analytical-like solution
    # x(t) = exp(-gamma/2 * t) * cos(sqrt(k) * t)
    gamma = 0.1
    k = 5.0
    x = np.exp(-gamma/2 * t) * np.cos(np.sqrt(k) * t)
    # Add small noise
    x += np.random.normal(0, 0.05, steps)

    with open(filename, 'w') as f:
        f.write("time,x\n")
        for i in range(steps):
            f.write(f"{t[i]},{x[i]}\n")

def generate_evil(filename):
    dt = 0.01
    steps = 1000
    t = np.arange(steps) * dt
    gamma = 0.1
    k = 5.0
    x = np.exp(-gamma/2 * t) * np.cos(np.sqrt(k) * t)

    # Inject a large spike
    spike_idx = np.random.randint(100, 900)
    x[spike_idx] += 15.0  # Big jump to trigger dE > 10 or E > 50

    with open(filename, 'w') as f:
        f.write("time,x\n")
        for i in range(steps):
            f.write(f"{t[i]},{x[i]}\n")

for i in range(100):
    generate_clean(f"/app/data/clean/traj_{i:03d}.csv")
    generate_evil(f"/app/data/evil/traj_{i:03d}.csv")

EOF

python3 /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
