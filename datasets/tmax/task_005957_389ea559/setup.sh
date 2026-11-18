#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network_diffusion.c
#include <stdio.h>
#include <math.h>

int main() {
    double beta = 0.5;
    double T = 5.0;
    double dt = 2.5; // BUG: This step size is too large and causes divergence
    int steps = (int)(T / dt);

    // Laplacian for a 4-node line graph
    double L[4][4] = {
        { 1, -1,  0,  0},
        {-1,  2, -1,  0},
        { 0, -1,  2, -1},
        { 0,  0, -1,  1}
    };

    double x[4] = {1.0, 0.0, 0.0, 0.0};
    double x_new[4];

    for (int step = 0; step < steps; step++) {
        for (int i = 0; i < 4; i++) {
            double Lx = 0.0;
            for (int j = 0; j < 4; j++) {
                Lx += L[i][j] * x[j];
            }
            x_new[i] = x[i] - dt * beta * Lx;
        }
        for (int i = 0; i < 4; i++) {
            x[i] = x_new[i];
        }
    }

    printf("Final state: %f %f %f %f\n", x[0], x[1], x[2], x[3]);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
