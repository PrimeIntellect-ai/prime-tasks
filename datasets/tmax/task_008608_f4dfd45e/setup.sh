#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulate_decay.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Box-Muller transform for normal distribution
double randn(double mu, double sigma) {
    double U1, U2, W, mult;
    static double X1, X2;
    static int call = 0;
    if (call == 1) {
        call = !call;
        return (mu + sigma * (double) X2);
    }
    do {
        U1 = -1 + ((double) rand() / RAND_MAX) * 2;
        U2 = -1 + ((double) rand() / RAND_MAX) * 2;
        W = pow(U1, 2) + pow(U2, 2);
    } while (W >= 1 || W == 0);
    mult = sqrt((-2 * log(W)) / W);
    X1 = U1 * mult;
    X2 = U2 * mult;
    call = !call;
    return (mu + sigma * (double) X1);
}

int main() {
    srand(42);
    int N = 100;
    double t_max = 10.0;
    printf("t,y\n");
    for (int i = 0; i < N; i++) {
        double t = i * (t_max / (N - 1));
        // True model: 5*exp(-1.5*t) + 2*exp(-0.2*t) + noise
        double y_true = 5.0 * exp(-1.5 * t) + 2.0 * exp(-0.2 * t);
        double y_noisy = y_true + randn(0.0, 0.1);
        printf("%.4f,%.4f\n", t, y_noisy);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
