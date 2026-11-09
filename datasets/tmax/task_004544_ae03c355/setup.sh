#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_noise.py
import numpy as np
np.random.seed(42)
noise = np.random.randn(10000000).astype(np.float64)
noise.tofile('/home/user/noise.bin')
EOF

    python3 /home/user/generate_noise.py

    cat << 'EOF' > /home/user/sim.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("/home/user/noise.bin", "rb");
    if (!f) return 1;
    double *noise = malloc(10000000 * sizeof(double));
    fread(noise, sizeof(double), 10000000, f);
    fclose(f);

    FILE *out = fopen("/home/user/baseline.txt", "w");
    for (int t = 0; t < 10000; t++) {
        double x = 2.0;
        for (int s = 0; s < 1000; s++) {
            double z = noise[t * 1000 + s];
            x = x - 0.05 * x * x * x + 0.1 * z;
        }
        fprintf(out, "%.15g\n", x);
    }
    fclose(out);
    free(noise);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
