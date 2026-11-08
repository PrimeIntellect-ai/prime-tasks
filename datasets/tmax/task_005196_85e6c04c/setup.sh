#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/simulation

    cat << 'EOF' > /home/user/raw_obs.csv
id,x,value,sensor_type
1,0.8,0.22,A1
2,0.2,0.55,B2
3,0.5,0.88,A1
4,0.1,0.11,C3
5,0.9,0.33,B2
EOF

    cat << 'EOF' > /home/user/simulation/solver.h
#ifndef SOLVER_H
#define SOLVER_H

void solve_system(double** A, double* b, int N, double* x_out);
double forward_model(double alpha, double x);

#endif
EOF

    cat << 'EOF' > /home/user/simulation/solver.cpp
#include "solver.h"
#include <cmath>
#include <iostream>

void solve_system(double** A, double* b, int N, double* x_out) {
    // AGENT MUST ADD REGULARIZATION HERE:
    // for(int i=0; i<N; ++i) A[i][i] += 1e-5;

    // Naive Gaussian Elimination
    for (int i = 0; i < N; i++) {
        // No pivoting, crashes if A[i][i] is 0
        for (int k = i + 1; k < N; k++) {
            double term = A[k][i] / A[i][i];
            for (int j = 0; j < N; j++) {
                A[k][j] -= term * A[i][j];
            }
            b[k] -= term * b[i];
        }
    }

    // Back substitution
    for (int i = N - 1; i >= 0; i--) {
        x_out[i] = b[i];
        for (int j = i + 1; j < N; j++) {
            x_out[i] -= A[i][j] * x_out[j];
        }
        x_out[i] = x_out[i] / A[i][i];
    }
}

double forward_model(double alpha, double x) {
    int N = 3;
    double** A = new double*[N];
    for(int i=0; i<N; i++) A[i] = new double[N];
    double* b = new double[N];
    double* x_out = new double[N];

    // Construct a matrix that becomes singular when alpha -> 0
    A[0][0] = alpha; A[0][1] = -alpha; A[0][2] = 0;
    A[1][0] = -alpha; A[1][1] = 2*alpha; A[1][2] = -alpha;
    A[2][0] = 0; A[2][1] = -alpha; A[2][2] = alpha;

    b[0] = 1.0; b[1] = 0.0; b[2] = -1.0;

    solve_system(A, b, N, x_out);

    double result = x_out[1] * x; // simplified dummy model

    for(int i=0; i<N; i++) delete[] A[i];
    delete[] A;
    delete[] b;
    delete[] x_out;

    return result;
}
EOF

    cat << 'EOF' > /home/user/simulation/main.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include "solver.h"

int main() {
    std::ifstream obs_file("/home/user/clean_obs.txt");
    if (!obs_file.is_open()) {
        std::cerr << "Could not open clean_obs.txt\n";
        return 1;
    }

    std::vector<double> xs, vals;
    double tx, tv;
    while (obs_file >> tx >> tv) {
        xs.push_back(tx);
        vals.push_back(tv);
    }

    // MCMC Setup
    double alpha = 1.0;
    int iterations = 10000;
    double sum_alpha = 0;
    int accepted = 0;

    // Pseudo-random for reproducibility
    auto my_rand = []() {
        static unsigned long int next = 1;
        next = next * 1103515245 + 12345;
        return (unsigned int)(next/65536) % 32768 / 32768.0;
    };

    for (int i = 0; i < iterations; i++) {
        double proposed_alpha = alpha + (my_rand() - 0.5) * 0.1;

        // Let it propose near-zero or negative to trigger the crash if unpatched
        if (i == 50) proposed_alpha = 0.0; 

        double current_ll = 0;
        double proposed_ll = 0;

        for (size_t j = 0; j < xs.size(); j++) {
            double cur_pred = forward_model(alpha, xs[j]);
            double prop_pred = forward_model(proposed_alpha, xs[j]);

            // basic Gaussian likelihood
            current_ll -= std::pow(vals[j] - cur_pred, 2);
            proposed_ll -= std::pow(vals[j] - prop_pred, 2);
        }

        if (std::exp(proposed_ll - current_ll) > my_rand()) {
            alpha = proposed_alpha;
            accepted++;
        }

        // discard burn-in
        if (i >= 2000) {
            sum_alpha += alpha;
        }
    }

    double mean_alpha = sum_alpha / 8000.0;

    std::ofstream out("/home/user/posterior_mean.txt");
    out << mean_alpha << "\n";
    out.close();

    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
