#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest numpy scipy

mkdir -p /home/user/sim

cat << 'EOF' > /home/user/sim/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double randn() {
    double u1 = ((double) rand() / RAND_MAX);
    double u2 = ((double) rand() / RAND_MAX);
    if (u1 <= 0.0) u1 = 1e-7;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <seed> <N>\n", argv[0]);
        return 1;
    }
    int seed = atoi(argv[1]);
    int N = atoi(argv[2]);
    srand(seed);

    for (int i = 0; i < N; i++) {
        double val = randn() * 1.5 + 0.5;
        // Artifact introduced by mesh size N
        val += 500.0 / N;
        printf("%.6f\n", val);
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
