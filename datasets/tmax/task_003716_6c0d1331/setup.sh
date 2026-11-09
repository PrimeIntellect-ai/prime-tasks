#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ python3-numpy
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data
    cd /home/user

    # Create near-singular input data (100x20)
    python3 -c "
import numpy as np
np.random.seed(42)
base = np.random.rand(10, 20)
# Duplicate rows to make it near-singular
V = np.tile(base, (10, 1))
# Add very tiny noise
V += np.random.rand(100, 20) * 1e-6
np.savetxt('/home/user/data/input_matrix.txt', V, fmt='%.6f')
"

    # Create nmf_solver.cpp
    cat << 'EOF' > /home/user/src/nmf_solver.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <sstream>
#include <cmath>
#include <cstdlib>

using namespace std;

typedef vector<vector<double>> Matrix;

Matrix read_matrix(const string& filename) {
    Matrix M;
    ifstream file(filename);
    string line;
    while (getline(file, line)) {
        vector<double> row;
        stringstream ss(line);
        double val;
        while (ss >> val) row.push_back(val);
        if (!row.empty()) M.push_back(row);
    }
    return M;
}

void write_matrix(const Matrix& M, const string& filename) {
    ofstream file(filename);
    for (const auto& row : M) {
        for (size_t i = 0; i < row.size(); ++i) {
            file << row[i] << (i == row.size() - 1 ? "" : " ");
        }
        file << "\n";
    }
}

Matrix transpose(const Matrix& M) {
    Matrix T(M[0].size(), vector<double>(M.size()));
    for (size_t i = 0; i < M.size(); ++i)
        for (size_t j = 0; j < M[0].size(); ++j)
            T[j][i] = M[i][j];
    return T;
}

Matrix multiply(const Matrix& A, const Matrix& B) {
    Matrix C(A.size(), vector<double>(B[0].size(), 0.0));
    for (size_t i = 0; i < A.size(); ++i)
        for (size_t j = 0; j < B[0].size(); ++j)
            for (size_t k = 0; k < A[0].size(); ++k)
                C[i][j] += A[i][k] * B[k][j];
    return C;
}

int main(int argc, char** argv) {
    if (argc != 5) return 1;
    Matrix V = read_matrix(argv[1]);
    int rank = stoi(argv[2]);
    string w_out = argv[3];
    string h_out = argv[4];

    int n = V.size();
    int m = V[0].size();

    Matrix W(n, vector<double>(rank));
    Matrix H(rank, vector<double>(m));

    srand(42);
    for (int i = 0; i < n; ++i)
        for (int k = 0; k < rank; ++k)
            W[i][k] = (rand() % 1000) / 1000.0 + 0.1;

    for (int k = 0; k < rank; ++k)
        for (int j = 0; j < m; ++j)
            H[k][j] = (rand() % 1000) / 1000.0 + 0.1;

    for (int iter = 0; iter < 100; ++iter) {
        // Update H
        Matrix W_T = transpose(W);
        Matrix W_T_V = multiply(W_T, V);
        Matrix W_T_W_H = multiply(multiply(W_T, W), H);
        for (int k = 0; k < rank; ++k) {
            for (int j = 0; j < m; ++j) {
                // BUG: No regularization on denominator
                H[k][j] *= W_T_V[k][j] / W_T_W_H[k][j];
            }
        }

        // Update W
        Matrix H_T = transpose(H);
        Matrix V_H_T = multiply(V, H_T);
        Matrix W_H_H_T = multiply(W, multiply(H, H_T));
        for (int i = 0; i < n; ++i) {
            for (int k = 0; k < rank; ++k) {
                // BUG: No regularization on denominator
                W[i][k] *= V_H_T[i][k] / W_H_H_T[i][k];
            }
        }
    }

    write_matrix(W, w_out);
    write_matrix(H, h_out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
