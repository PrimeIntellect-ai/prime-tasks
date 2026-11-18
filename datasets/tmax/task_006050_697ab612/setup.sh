#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mcmc_degrade.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Observation
double y_obs = 4.9787;
double T = 10.0;
double y_0 = 100.0;

// Log-likelihood function with buggy ODE integrator
double log_likelihood(double theta) {
    double y = y_0;
    double t = 0.0;
    double dt = 2.0; // BUG: step size too large

    // Euler integration
    while (t < T) {
        y = y - theta * y * dt;
        t += dt;
    }

    // Gaussian error model with sigma = 0.5
    double sigma = 0.5;
    double diff = y - y_obs;
    return -0.5 * (diff * diff) / (sigma * sigma);
}

// Uniform prior U(0, 1)
double log_prior(double theta) {
    if (theta > 0.0 && theta < 1.0) return 0.0;
    return -1e9;
}

double runif() {
    return (double)rand() / (double)RAND_MAX;
}

double rnorm() {
    double u1 = runif();
    double u2 = runif();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int seed = atoi(argv[1]);
    srand(seed);

    int iterations = 5500;
    double theta_current = 0.5;
    double ll_current = log_likelihood(theta_current);

    for (int i = 0; i < iterations; i++) {
        double theta_prop = theta_current + rnorm() * 0.05;
        double ll_prop = log_likelihood(theta_prop);

        double lp_current = log_prior(theta_current);
        double lp_prop = log_prior(theta_prop);

        double log_accept_ratio = (ll_prop + lp_prop) - (ll_current + lp_current);

        if (log(runif()) < log_accept_ratio) {
            theta_current = theta_prop;
            ll_current = ll_prop;
        }

        printf("%f\n", theta_current);
    }

    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
