#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libeigen3-dev
    pip3 install pytest

    mkdir -p /home/user/bio_mcmc
    cd /home/user/bio_mcmc

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -O3 -std=c++14 -I/usr/include/eigen3
TARGET = mcmc_sampler
OBJS = main.o likelihood.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS)

main.o: main.cpp likelihood.h
	$(CXX) $(CXXFLAGS) -c main.cpp

likelihood.o: likelihood.cpp likelihood.h
	$(CXX) $(CXXFLAGS) -c likelihood.cpp

clean:
	rm -f $(OBJS) $(TARGET)
EOF

    cat << 'EOF' > likelihood.h
#ifndef LIKELIHOOD_H
#define LIKELIHOOD_H
#include <Eigen/Dense>

double compute_log_likelihood(const Eigen::VectorXd& x, const Eigen::VectorXd& mu, const Eigen::MatrixXd& cov);

#endif
EOF

    cat << 'EOF' > likelihood.cpp
#include "likelihood.h"
#include <cmath>
#include <iostream>

const double PI = 3.14159265358979323846;

double compute_log_likelihood(const Eigen::VectorXd& x, const Eigen::VectorXd& mu, const Eigen::MatrixXd& cov) {
    Eigen::LLT<Eigen::MatrixXd> llt(cov);
    if (llt.info() == Eigen::NumericalIssue) {
        // Failing here due to near-singular input
        return -INFINITY;
    }

    Eigen::MatrixXd L = llt.matrixL();
    double log_det = 0.0;
    for (int i = 0; i < L.rows(); ++i) {
        log_det += 2.0 * std::log(L(i, i));
    }

    Eigen::VectorXd diff = x - mu;
    Eigen::VectorXd sol = llt.solve(diff);

    return -0.5 * (x.size() * std::log(2.0 * PI) + log_det + diff.dot(sol));
}
EOF

    cat << 'EOF' > main.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <random>
#include "likelihood.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;

    int n_dim = 5;
    Eigen::VectorXd x = Eigen::VectorXd::Zero(n_dim);
    Eigen::VectorXd mu = Eigen::VectorXd::Zero(n_dim);

    // Create a deterministically near-singular covariance matrix
    Eigen::MatrixXd cov = Eigen::MatrixXd::Ones(n_dim, n_dim);
    for(int i=0; i<n_dim; ++i) cov(i,i) += 1e-10; // Practically singular for LLT

    // MCMC Setup
    std::mt19937 gen(42);
    std::normal_distribution<double> prop_dist(0.0, 0.1);
    std::uniform_real_distribution<double> uni_dist(0.0, 1.0);

    Eigen::VectorXd current_theta = Eigen::VectorXd::Zero(3);
    double current_ll = compute_log_likelihood(x, mu, cov); // Will be -inf initially

    Eigen::VectorXd sum_theta = Eigen::VectorXd::Zero(3);
    int accepted = 0;

    for(int i=0; i<5000; ++i) {
        Eigen::VectorXd prop_theta = current_theta;
        for(int j=0; j<3; ++j) prop_theta(j) += prop_dist(gen);

        // Dummy mapping from theta to mu/cov to force evaluation
        for(int j=0; j<n_dim; ++j) mu(j) = prop_theta(0) * 0.1;

        double prop_ll = compute_log_likelihood(x, mu, cov);

        // Prior (standard normal)
        double current_prior = -0.5 * current_theta.squaredNorm();
        double prop_prior = -0.5 * prop_theta.squaredNorm();

        double log_alpha = (prop_ll + prop_prior) - (current_ll + current_prior);

        if (std::log(uni_dist(gen)) < log_alpha || current_ll == -INFINITY) {
            current_theta = prop_theta;
            current_ll = prop_ll;
            accepted++;
        }
        sum_theta += current_theta;
    }

    Eigen::VectorXd mean_theta = sum_theta / 5000.0;
    std::cout << mean_theta(0) << "," << mean_theta(1) << "," << mean_theta(2) << std::endl;
    return 0;
}
EOF

    echo "dummy_data" > data.csv

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/bio_mcmc
    chmod -R 777 /home/user
