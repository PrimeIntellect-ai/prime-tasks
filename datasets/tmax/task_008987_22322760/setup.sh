#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/data.csv
1.0, 2.1
1.01, 2.12
1.02, 2.15
1.03, 2.14
2.0, 5.8
2.01, 5.85
2.02, 5.9
3.0, 11.2
3.01, 11.25
3.02, 11.3
EOF

    cat << 'EOF' > /home/user/app/poly_fit.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define DEGREE 3
#define N_COEFFS (DEGREE + 1)

// Basic LU decomposition solver (no pivoting for simplicity)
// Solves Mx = B. M is replaced by its LU decomposition.
void solve_lu(double M[N_COEFFS][N_COEFFS], double B[N_COEFFS], double X[N_COEFFS]) {
    for (int i = 0; i < N_COEFFS; i++) {
        for (int j = i + 1; j < N_COEFFS; j++) {
            double factor = M[j][i] / M[i][i];
            for (int k = i; k < N_COEFFS; k++) {
                M[j][k] -= factor * M[i][k];
            }
            B[j] -= factor * B[i];
        }
    }
    for (int i = N_COEFFS - 1; i >= 0; i--) {
        X[i] = B[i];
        for (int j = i + 1; j < N_COEFFS; j++) {
            X[i] -= M[i][j] * X[j];
        }
        X[i] /= M[i][i];
    }
}

double integrate_poly(double* coeffs, int degree, double start, double end) {
    // TODO: Implement analytical definite integral
    return 0.0;
}

int main() {
    FILE *fp = fopen("data.csv", "r");
    if (!fp) return 1;

    double x[100], y[100];
    int n = 0;
    while (fscanf(fp, "%lf, %lf", &x[n], &y[n]) == 2) {
        n++;
    }
    fclose(fp);

    double ATA[N_COEFFS][N_COEFFS] = {0};
    double ATB[N_COEFFS] = {0};

    for (int i = 0; i < n; i++) {
        double px[N_COEFFS];
        px[0] = 1.0;
        for (int j = 1; j < N_COEFFS; j++) px[j] = px[j-1] * x[i];

        for (int r = 0; r < N_COEFFS; r++) {
            ATB[r] += px[r] * y[i];
            for (int c = 0; c < N_COEFFS; c++) {
                ATA[r][c] += px[r] * px[c];
            }
        }
    }

    // TODO: Add regularization here

    double coeffs[N_COEFFS] = {0};
    solve_lu(ATA, ATB, coeffs);

    double integral = integrate_poly(coeffs, DEGREE, 0.0, 10.0);

    FILE *out = fopen("output.txt", "w");
    fprintf(out, "Coefficients:\n");
    for (int i = 0; i < N_COEFFS; i++) {
        fprintf(out, "c%d = %.4f\n", i, coeffs[i]);
    }
    fprintf(out, "Integral(0 to 10): %.4f\n", integral);
    fclose(out);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
