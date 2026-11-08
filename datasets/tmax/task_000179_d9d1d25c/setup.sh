#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/naive_solver.c
#include <stdio.h>
#include <stdlib.h>

// Naive Gaussian elimination without partial pivoting
void solve_system(double* A, double* b, int n, double* x) {
    double** mat = (double**)malloc(n * sizeof(double*));
    for (int i = 0; i < n; i++) {
        mat[i] = (double*)malloc((n + 1) * sizeof(double));
        for (int j = 0; j < n; j++) {
            mat[i][j] = A[i * n + j];
        }
        mat[i][n] = b[i];
    }

    for (int k = 0; k < n - 1; k++) {
        for (int i = k + 1; i < n; i++) {
            double factor = mat[i][k] / mat[k][k];
            for (int j = k; j < n + 1; j++) {
                mat[i][j] -= factor * mat[k][j];
            }
        }
    }

    for (int i = n - 1; i >= 0; i--) {
        x[i] = mat[i][n];
        for (int j = i + 1; j < n; j++) {
            x[i] -= mat[i][j] * x[j];
        }
        x[i] /= mat[i][i];
    }

    for (int i = 0; i < n; i++) {
        free(mat[i]);
    }
    free(mat);
}
EOF

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
n_samples = 150
n_features = 5

X = np.random.randn(n_samples, n_features - 1)
# Create near perfect collinearity
collinear_col = X[:, 0] * 0.5 + X[:, 1] * 0.5 + np.random.randn(n_samples) * 1e-10
X = np.column_stack([X, collinear_col])

true_beta = np.array([1.5, -2.0, 3.1, 0.5, 1.0])
y = X @ true_beta + np.random.randn(n_samples) * 0.5

pd.DataFrame(X).to_csv('/home/user/X.csv', index=False, header=False)
pd.DataFrame(y).to_csv('/home/user/y.csv', index=False, header=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
