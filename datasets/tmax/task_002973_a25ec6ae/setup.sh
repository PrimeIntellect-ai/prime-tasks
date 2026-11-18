#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest matplotlib pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.txt
5.14
6.22
4.89
5.71
3.95
8.01
6.55
4.33
5.99
7.12
3.50
5.66
6.08
4.44
5.82
5.50
6.30
4.90
5.20
6.80
EOF

    cat << 'EOF' > /home/user/mcmc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N_ITERS 10000
#define N_DATA 20

// Custom LCG for reproducible "randomness" across platforms
unsigned long lcg_seed = 42;
double my_rand() {
    lcg_seed = (1103515245 * lcg_seed + 12345) % 2147483648;
    return (double)lcg_seed / 2147483648.0;
}
double my_randn() {
    double u1 = my_rand();
    double u2 = my_rand();
    return sqrt(-2.0 * log(u1 + 1e-15)) * cos(2.0 * M_PI * u2);
}

// INEFFICIENT LIKELIHOOD FUNCTION
// The bottleneck: it reads the file on every single call!
double log_likelihood(double mu, double sigma, double *data, int n) {
    if (sigma <= 0) return -1e9;

    double ll = 0.0;
    FILE *f = fopen("/home/user/data.txt", "r");
    if (!f) return -1e9;

    double val;
    while(fscanf(f, "%lf", &val) == 1) {
        ll += -log(sigma) - 0.5 * pow((val - mu)/sigma, 2);
    }
    fclose(f);

    return ll;
}

int main() {
    double data[N_DATA];
    FILE *f = fopen("/home/user/data.txt", "r");
    for(int i=0; i<N_DATA; i++) {
        fscanf(f, "%lf", &data[i]);
    }
    fclose(f);

    double current_mu = 0.0;
    double current_sigma = 1.0;
    double current_ll = log_likelihood(current_mu, current_sigma, data, N_DATA);

    for (int i = 0; i < N_ITERS; i++) {
        double prop_mu = current_mu + my_randn() * 0.5;
        double prop_sigma = current_sigma + my_randn() * 0.5;

        double prop_ll = log_likelihood(prop_mu, prop_sigma, data, N_DATA);

        double accept_prob = exp(prop_ll - current_ll);
        if (my_rand() < accept_prob) {
            current_mu = prop_mu;
            current_sigma = prop_sigma;
            current_ll = prop_ll;
        }

        printf("%f,%f\n", current_mu, current_sigma);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
