#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget tar make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mcmc_sequence.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <random>
#include <cmath>
#include <Eigen/Dense>

using namespace Eigen;
using namespace std;

// Target distribution: Multivariate Normal with known mean and covariance
Vector3d target_mean(2.5, -1.0, 3.1);
Matrix3d target_cov;
Matrix3d target_cov_inv;

double log_target_density(const Vector3d& x) {
    Vector3d diff = x - target_mean;
    return -0.5 * diff.transpose() * target_cov_inv * diff;
}

// BUGGY FUNCTION: Needs to be fixed by the agent
Vector3d generate_proposal(const Vector3d& current, const Matrix3d& covariance, mt19937& gen) {
    normal_distribution<double> d(0.0, 1.0);
    Vector3d z(d(gen), d(gen), d(gen));

    // BUG: Direct multiplication by covariance instead of Cholesky factor L
    Vector3d proposal = current + covariance * z;
    return proposal;
}

int main() {
    target_cov << 1.0, 0.2, 0.1,
                  0.2, 1.0, 0.2,
                  0.1, 0.2, 1.0;
    target_cov_inv = target_cov.inverse();

    Matrix3d proposal_cov;
    proposal_cov << 0.5, 0.1, 0.05,
                    0.1, 0.5, 0.1,
                    0.05, 0.1, 0.5;

    mt19937 gen(42);
    uniform_real_distribution<double> u(0.0, 1.0);

    Vector3d current(0.0, 0.0, 0.0);
    double current_log_prob = log_target_density(current);

    int num_iterations = 100000;
    int burn_in = 20000;

    Vector3d sum_posterior = Vector3d::Zero();
    int accepted = 0;

    for (int i = 0; i < num_iterations; ++i) {
        Vector3d proposal = generate_proposal(current, proposal_cov, gen);
        double proposal_log_prob = log_target_density(proposal);

        if (log(u(gen)) < (proposal_log_prob - current_log_prob)) {
            current = proposal;
            current_log_prob = proposal_log_prob;
            accepted++;
        }

        if (i >= burn_in) {
            sum_posterior += current;
        }
    }

    Vector3d posterior_mean = sum_posterior / (num_iterations - burn_in);

    ofstream outfile("/home/user/posterior_mean.csv");
    outfile << posterior_mean(0) << "," << posterior_mean(1) << "," << posterior_mean(2) << endl;
    outfile.close();

    return 0;
}
EOF

    chmod -R 777 /home/user
