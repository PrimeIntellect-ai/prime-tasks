#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/diffusion.c
#include <stdio.h>
#include <math.h>

#define N 5
double A[N][N] = {
    { -2, 1, 0, 0, 1 },
    { 1, -2, 1, 0, 0 },
    { 0, 1, -2, 1, 0 },
    { 0, 0, 1, -2, 1 },
    { 1, 0, 0, 1, -2 }
};

void deriv(double *x, double *dxdt) {
    for(int i=0; i<N; i++) {
        dxdt[i] = 0;
        for(int j=0; j<N; j++) {
            dxdt[i] += A[i][j] * x[j];
        }
    }
}

int main() {
    double x[N] = {10.0, 0.0, 0.0, 0.0, 0.0};
    double t = 0.0, t_end = 2.0;
    double dt = 0.1, tol = 1e-4;

    while (t < t_end) {
        if (t + dt > t_end) dt = t_end - t;

        double dxdt[N], x1[N], dxdt1[N], x2[N];
        deriv(x, dxdt);

        // Full step Euler
        for(int i=0; i<N; i++) x1[i] = x[i] + dxdt[i] * dt;

        // Two half steps Euler
        double x_half[N], dxdt_half[N];
        for(int i=0; i<N; i++) x_half[i] = x[i] + dxdt[i] * (dt/2.0);
        deriv(x_half, dxdt_half);
        for(int i=0; i<N; i++) x2[i] = x_half[i] + dxdt_half[i] * (dt/2.0);

        double err = 0.0;
        for(int i=0; i<N; i++) err += fabs(x1[i] - x2[i]);
        err = err / N + 1e-16;

        // BUG: Step size grows with error instead of shrinking
        double dt_new = dt * sqrt(err / tol);

        if (err <= tol) {
            for(int i=0; i<N; i++) x[i] = x2[i];
            t += dt;
        }
        dt = dt_new;

        // Safety limits
        if (dt > 0.5) dt = 0.5;
        if (dt < 1e-6) {
            printf("Step size too small!\n");
            return 1;
        }
    }

    for(int i=0; i<N; i++) {
        printf("%.4f ", x[i]);
    }
    printf("\n");
    return 0;
}
EOF

    chmod -R 777 /home/user
