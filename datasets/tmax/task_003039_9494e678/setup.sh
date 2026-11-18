#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/integrator.c
#include <stdio.h>
#include <math.h>

void step_update(double *h, double error, double tol) {
    if (error <= 0) error = 1e-15;
    // Bug: error and tol are inverted
    *h = *h * 0.9 * pow(error / tol, 0.2);
}

int main() {
    double x = 1.0, y = 0.0;
    double h = 0.1;
    double tol = 1e-6;

    FILE *f = fopen("/home/user/output.bin", "wb");
    if (!f) return 1;

    for (int i = 0; i < 1000; i++) {
        double error = h * h * 0.5; // Simplified synthetic error estimation
        step_update(&h, error, tol);

        // Simple integration step
        x += y * h;
        y -= x * h;

        double out[2] = {x, y};
        fwrite(out, sizeof(double), 2, f);
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
