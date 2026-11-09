#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/matrix_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

void cholesky(double A[3][3], double L[3][3]) {
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j <= i; j++) {
            double sum = 0;
            for (int k = 0; k < j; k++) {
                sum += L[i][k] * L[j][k];
            }
            if (i == j) {
                double val = A[i][i] - sum;
                if (val <= 0.0) {
                    printf("DIVERGED\n");
                    exit(0);
                }
                L[i][j] = sqrt(val);
            } else {
                L[i][j] = (1.0 / L[j][j] * (A[i][j] - sum));
            }
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double dt = atof(argv[1]);

    // Initial matrix (symmetric positive definite)
    double A[3][3] = {
        {4.0, 1.0, 1.0},
        {1.0, 5.0, 2.0},
        {1.0, 2.0, 6.0}
    };

    // Simulate evolution
    for (int step = 0; step < 100; step++) {
        A[0][0] -= dt * 0.52;
        A[1][1] -= dt * 0.2;
        A[2][2] -= dt * 0.1;

        double L[3][3] = {0};
        cholesky(A, L);
    }
    printf("SUCCESS\n");
    return 0;
}
EOF

    chmod -R 777 /home/user
