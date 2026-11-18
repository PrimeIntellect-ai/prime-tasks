#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np
np.random.seed(42)
N = 10000
# Create values that will cause precision loss in naive sum
values = []
for i in range(N):
    if i % 2 == 0:
        values.append(100000.0 + np.random.random())
    else:
        values.append(-100000.0 + np.random.random())

with open('molecule.dat', 'w') as f:
    f.write(f"{N}\n")
    for v in values:
        f.write(f"{v}\n")
EOF
    python3 generate_data.py

    cat << 'EOF' > model_fit.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    FILE *f = fopen("/home/user/molecule.dat", "r");
    if (!f) return 1;

    int N;
    fscanf(f, "%d", &N);

    double *potentials = (double*)malloc(N * sizeof(double));
    for (int i = 0; i < N; i++) {
        fscanf(f, "%lf", &potentials[i]);
    }
    fclose(f);

    // Simulated Graph Jacobi Iteration (Dummy operation for the scenario)
    for (int iter = 0; iter < 10; iter++) {
        for (int i = 1; i < N - 1; i++) {
            potentials[i] = (potentials[i-1] + potentials[i+1] + potentials[i]) / 3.0;
        }
    }

    // NAIVE SUMMATION (To be replaced by the agent)
    double total_energy = 0.0;
    for (int i = 0; i < N; i++) {
        total_energy += potentials[i];
    }

    printf("Total Energy: %.10f\n", total_energy);

    free(potentials);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
