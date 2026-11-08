#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    int n = 1000;
    // Hardcoded seed for deterministic data generation
    srand(1042);
    for(int i = 0; i < n; i++) {
        // Generate values from a simulated skewed distribution
        double u1 = (double)rand() / RAND_MAX;
        double u2 = (double)rand() / RAND_MAX;
        double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
        double val = exp(z0 * 0.5 + 2.0); // Log-normalish
        printf("%.6f\n", val);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
