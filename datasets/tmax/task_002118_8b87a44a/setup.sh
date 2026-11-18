#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy scipy

    mkdir -p /app
    cat << 'EOF' > /app/oracle_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double rand_normal() {
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int N = atoi(argv[1]);
    srand(42); // fixed seed for exact reproducibility if needed, or time(NULL)
    for (int i=0; i<N; i++) {
        double n = rand_normal();
        double val = exp(n * 0.5 + 1.0);
        printf("%.6f\n", val);
    }
    return 0;
}
EOF

    gcc -O3 /app/oracle_sim.c -o /app/oracle_sim -lm
    strip /app/oracle_sim
    chmod +x /app/oracle_sim
    rm /app/oracle_sim.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
