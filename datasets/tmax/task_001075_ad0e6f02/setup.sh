#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/integrator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char* argv[]) {
    if (argc != 5) return 1;
    double r = atof(argv[1]);
    double v = atof(argv[2]);
    double dt = atof(argv[3]);
    int steps = atoi(argv[4]);

    for (int i = 0; i < steps; i++) {
        double a = -1.0 / (r * r);
        r += v * dt;
        v += a * dt;
        // The quirky adaptation
        dt = dt * 1.01; 
        if (dt > 0.5) {
            dt = 0.5; // caps out, causing potential divergence
        }
    }
    printf("%.6f %.6f\n", r, v);
    return 0;
}
EOF

    gcc -O2 /tmp/integrator.c -o /app/binary_integrator
    strip /app/binary_integrator
    chmod +x /app/binary_integrator
    rm /tmp/integrator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
