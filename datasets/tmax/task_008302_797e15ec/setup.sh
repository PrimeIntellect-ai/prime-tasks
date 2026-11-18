#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_matrix.py
import numpy as np
np.random.seed(42)
# Near-singular, poorly scaled matrix
U = np.random.randn(100, 1) * 5
V = np.random.randn(100, 1) * 5
A = U.dot(V.T) + np.random.randn(100, 100) * 0.1
np.savetxt('matrix.txt', A, fmt='%.4f')
EOF
    python3 generate_matrix.py

    cat << 'EOF' > mf.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>

using namespace std;

int main() {
    int N = 100;
    vector<vector<double>> A(N, vector<double>(N));
    ifstream infile("matrix.txt");
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            infile >> A[i][j];
        }
    }

    vector<double> u(N, 0.1);
    vector<double> v(N, 0.1);

    double lr = 0.001;
    double lambda = 0.05;
    int iters = 100;

    for (int step = 0; step < iters; ++step) {
        vector<double> grad_u(N, 0.0);
        vector<double> grad_v(N, 0.0);

        // TODO: Add OpenMP pragmas and regularization to gradients
        for (int i = 0; i < N; ++i) {
            for (int j = 0; j < N; ++j) {
                double err = A[i][j] - u[i] * v[j];
                grad_u[i] += -2.0 * err * v[j];
            }
            // Add regularization here
        }

        for (int j = 0; j < N; ++j) {
            for (int i = 0; i < N; ++i) {
                double err = A[i][j] - u[i] * v[j];
                grad_v[j] += -2.0 * err * u[i];
            }
            // Add regularization here
        }

        for (int i = 0; i < N; ++i) u[i] -= lr * grad_u[i];
        for (int j = 0; j < N; ++j) v[j] -= lr * grad_v[j];
    }

    double loss = 0.0;
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            double err = A[i][j] - u[i] * v[j];
            loss += err * err;
        }
        loss += lambda * (u[i]*u[i] + v[i]*v[i]);
    }

    ofstream outfile("final_loss.txt");
    outfile << fixed << setprecision(4) << loss << endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
