#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/heat_opt.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 300
#define M 100
#define DX (1.0/(N-1))
#define DT (0.5/M)

// Inefficient Dense LU solve
void dense_lu_solve(double A[N][N], double b[N], double x[N]) {
    double L[N][N] = {0};
    double U[N][N] = {0};

    // LU Decomposition
    for (int i = 0; i < N; i++) {
        for (int k = i; k < N; k++) {
            double sum = 0;
            for (int j = 0; j < i; j++)
                sum += (L[i][j] * U[j][k]);
            U[i][k] = A[i][k] - sum;
        }
        for (int k = i; k < N; k++) {
            if (i == k)
                L[i][i] = 1;
            else {
                double sum = 0;
                for (int j = 0; j < i; j++)
                    sum += (L[k][j] * U[j][i]);
                L[k][i] = (A[k][i] - sum) / U[i][i];
            }
        }
    }

    // Forward substitution L * y = b (storing y in x)
    for (int i = 0; i < N; i++) {
        double sum = 0;
        for (int j = 0; j < i; j++) {
            sum += L[i][j] * x[j];
        }
        x[i] = b[i] - sum;
    }

    // Backward substitution U * x = y
    for (int i = N - 1; i >= 0; i--) {
        double sum = 0;
        for (int j = i + 1; j < N; j++) {
            sum += U[i][j] * x[j];
        }
        x[i] = (x[i] - sum) / U[i][i];
    }
}

void run_sim(double alpha, double final_state[N]) {
    double u[N];
    for(int i=0; i<N; i++) u[i] = sin(M_PI * i * DX);

    double r = alpha * DT / (DX * DX);
    static double A[N][N];

    for(int step=0; step<M; step++) {
        // Build matrix
        for(int i=0; i<N; i++) {
            for(int j=0; j<N; j++) A[i][j] = 0;
            if (i == 0 || i == N-1) {
                A[i][i] = 1.0;
            } else {
                A[i][i-1] = -r;
                A[i][i]   = 1.0 + 2.0*r;
                A[i][i+1] = -r;
            }
        }

        double b[N];
        for(int i=0; i<N; i++) {
            if (i == 0 || i == N-1) b[i] = 0;
            else b[i] = u[i];
        }

        // Solve system
        dense_lu_solve(A, b, u);
    }
    for(int i=0; i<N; i++) final_state[i] = u[i];
}

double cost(double alpha, double target[N]) {
    double current[N];
    run_sim(alpha, current);
    double err = 0;
    for(int i=0; i<N; i++) err += (current[i] - target[i])*(current[i] - target[i]);
    return err;
}

int main() {
    double target_state[N];
    run_sim(0.042, target_state); // Truth alpha is 0.042

    double alpha = 0.01;
    double lr = 0.005;
    double h = 1e-4;

    for(int iter=0; iter<10; iter++) {
        double c1 = cost(alpha, target_state);
        double c2 = cost(alpha + h, target_state);
        double grad = (c2 - c1) / h;
        alpha = alpha - lr * grad;
    }

    printf("%.6f\n", alpha);
    return 0;
}
EOF

    chmod -R 777 /home/user
