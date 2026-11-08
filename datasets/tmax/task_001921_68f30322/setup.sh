#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev bc gawk
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/stellar_core_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double randn(double mu, double sigma) {
    double U1 = (double)rand() / RAND_MAX;
    if (U1 == 0.0) U1 = 1e-8;
    double U2 = (double)rand() / RAND_MAX;
    double Z0 = sqrt(-2.0 * log(U1)) * cos(2.0 * M_PI * U2);
    return mu + Z0 * sigma;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double radius = atof(argv[1]);
    unsigned int seed;
    FILE* urandom = fopen("/dev/urandom", "r");
    if(urandom) {
        if(fread(&seed, sizeof(unsigned int), 1, urandom) != 1) {
            seed = 42;
        }
        fclose(urandom);
    } else {
        seed = 42;
    }
    srand(seed);
    double density = 50.0 * exp(-0.5 * radius);
    double noise = randn(0.0, 5.0);
    printf("Density: %f\n", density + noise);
    return 0;
}
EOF

gcc -O3 -o /app/stellar_core_sim /app/stellar_core_sim.c -lm
strip -s /app/stellar_core_sim
rm /app/stellar_core_sim.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
