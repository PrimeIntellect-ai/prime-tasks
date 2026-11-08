#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double exact(double x) {
    return sinh(1.0 - x) / sinh(1.0);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int N = atoi(argv[1]);
    int trials = 100;

    // Fixed seed for reproducible "noise"
    srand(42);

    FILE *f = fopen("/home/user/noisy_data.csv", "w");
    for (int t = 0; t < trials; t++) {
        for (int i = 0; i <= N; i++) {
            double x = (double)i / N;
            double val = exact(x);
            // Add uniform noise between -0.1 and 0.1
            double noise = ((double)rand() / RAND_MAX) * 0.2 - 0.1;
            fprintf(f, "%.6f", val + noise);
            if (i < N) fprintf(f, ",");
        }
        fprintf(f, "\n");
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
