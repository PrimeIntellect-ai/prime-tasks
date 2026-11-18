#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int nx = 100;
    double dx = 1.0 / (nx - 1);
    double alpha = 0.1;
    double T = 0.5;

    // TODO: Change N to the minimum integer value that ensures numerical stability
    int N = 100; 
    double dt = T / N;

    double* u = (double*)malloc(nx * sizeof(double));
    double* un = (double*)malloc(nx * sizeof(double));

    for(int i = 0; i < nx; i++) {
        double x = i * dx;
        u[i] = x * (1.0 - x) * 4.0;
    }

    for(int n = 0; n < N; n++) {
        for(int i = 1; i < nx - 1; i++) {
            un[i] = u[i] + alpha * dt / (dx * dx) * (u[i+1] - 2*u[i] + u[i-1]);
        }
        un[0] = 0.0;
        un[nx-1] = 0.0;
        for(int i = 0; i < nx; i++) {
            u[i] = un[i];
        }
    }

    double sum = 0.0;
    for(int i = 0; i < nx; i++) {
        sum += u[i];
    }

    printf("%.6f\n", sum);
    free(u);
    free(un);
    return 0;
}
EOF

    chmod -R 777 /home/user
