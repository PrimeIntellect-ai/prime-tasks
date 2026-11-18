#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cmake build-essential
pip3 install pytest

mkdir -p /app/libsvd_fast/src
mkdir -p /app/libsvd_fast/include

cat << 'EOF' > /app/libsvd_fast/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(libsvd_fast)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O0 -fPIC") # Perturbation: -O0 instead of -O3
add_library(svd_fast SHARED src/svd.cpp)
target_include_directories(svd_fast PUBLIC include)
EOF

cat << 'EOF' > /app/libsvd_fast/include/svd.h
#pragma once
#include <vector>

void compute_svd(const std::vector<std::vector<double>>& A,
                 std::vector<std::vector<double>>& U,
                 std::vector<double>& S,
                 std::vector<std::vector<double>>& V);
EOF

cat << 'EOF' > /app/libsvd_fast/src/svd.cpp
#include "svd.h"
#include <cmath>
#include <algorithm>

// Extremely basic, naive SVD via Jacobi rotations for square matrices
void compute_svd(const std::vector<std::vector<double>>& A,
                 std::vector<std::vector<double>>& U,
                 std::vector<double>& S,
                 std::vector<std::vector<double>>& V) {
    int n = A.size();
    U = A;
    V.assign(n, std::vector<double>(n, 0.0));
    for(int i=0; i<n; ++i) V[i][i] = 1.0;

    // Perturbation: Tolerance is too large
    const double CONVERGENCE_TOL = 1e-1; 

    bool changed = true;
    int max_iters = 100;
    while(changed && max_iters > 0) {
        changed = false;
        max_iters--;
        for(int p = 0; p < n - 1; ++p) {
            for(int q = p + 1; q < n; ++q) {
                double alpha = 0.0, beta = 0.0, gamma = 0.0;
                for(int k = 0; k < n; ++k) {
                    alpha += U[k][p] * U[k][p];
                    beta += U[k][q] * U[k][q];
                    gamma += U[k][p] * U[k][q];
                }

                if(std::abs(gamma) < CONVERGENCE_TOL) continue;
                changed = true;

                double zeta = (beta - alpha) / (2.0 * gamma);
                double t = std::copysign(1.0 / (std::abs(zeta) + std::sqrt(1.0 + zeta*zeta)), zeta);
                double c = 1.0 / std::sqrt(1.0 + t*t);
                double s = c * t;

                for(int k = 0; k < n; ++k) {
                    double ukp = U[k][p];
                    double ukq = U[k][q];
                    U[k][p] = c * ukp - s * ukq;
                    U[k][q] = s * ukp + c * ukq;

                    double vkp = V[k][p];
                    double vkq = V[k][q];
                    V[k][p] = c * vkp - s * vkq;
                    V[k][q] = s * vkp + c * vkq;
                }
            }
        }
    }

    S.assign(n, 0.0);
    for(int p = 0; p < n; ++p) {
        double norm = 0.0;
        for(int k = 0; k < n; ++k) norm += U[k][p] * U[k][p];
        S[p] = std::sqrt(norm);
        if(S[p] > 1e-12) {
            for(int k = 0; k < n; ++k) U[k][p] /= S[p];
        }
    }
}
EOF

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/regression_test.cpp
#include "svd.h"
#include <iostream>
#include <vector>
#include <chrono>
#include <fstream>
#include <cmath>
#include <random>

int main() {
    int n = 150;
    std::vector<std::vector<double>> A(n, std::vector<double>(n));
    std::mt19937 gen(42);
    std::normal_distribution<double> dist(0.0, 1.0);

    for(int i=0; i<n; ++i)
        for(int j=0; j<n; ++j)
            A[i][j] = dist(gen);

    std::vector<std::vector<double>> U, V;
    std::vector<double> S;

    auto start = std::chrono::high_resolution_clock::now();
    compute_svd(A, U, S, V);
    auto end = std::chrono::high_resolution_clock::now();

    double exec_time = std::chrono::duration<double>(end - start).count();

    double recon_error = 0.0;
    for(int i=0; i<n; ++i) {
        for(int j=0; j<n; ++j) {
            double val = 0.0;
            for(int k=0; k<n; ++k) {
                val += U[i][k] * S[k] * V[j][k];
            }
            double diff = A[i][j] - val;
            recon_error += diff * diff;
        }
    }
    recon_error = std::sqrt(recon_error);

    std::ofstream out("/home/user/metrics.json");
    out << "{\n";
    out << "  \"execution_time\": " << exec_time << ",\n";
    out << "  \"reconstruction_error\": " << recon_error << "\n";
    out << "}\n";

    return 0;
}
EOF

chmod -R 777 /app
chmod -R 777 /home/user
