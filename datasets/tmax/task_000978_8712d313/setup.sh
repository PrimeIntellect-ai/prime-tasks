#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc file binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/logistic_sim.c
#include <stdio.h>
#include <stdlib.h>

double f(double y, double r, double K) {
    return r * y * (1.0 - y / K);
}

int main(int argc, char *argv[]) {
    if (argc != 6) return 1;
    double y = atof(argv[1]);
    double r = atof(argv[2]);
    double K = atof(argv[3]);
    double dt = atof(argv[4]);
    int n_steps = atoi(argv[5]);

    for (int i = 0; i < n_steps; i++) {
        double k1 = f(y, r, K);
        double k2 = f(y + 0.5 * dt * k1, r, K);
        double k3 = f(y + 0.5 * dt * k2, r, K);
        double k4 = f(y + dt * k3, r, K);
        y = y + (dt / 6.0) * (k1 + 2.0*k2 + 2.0*k3 + k4);
    }
    printf("%.6f\n", y);
    return 0;
}
EOF

    gcc -O2 /app/logistic_sim.c -o /app/logistic_sim
    strip /app/logistic_sim
    rm /app/logistic_sim.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
