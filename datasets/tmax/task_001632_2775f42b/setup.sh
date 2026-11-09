#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /app/spectral-ode-sim-1.0

    cat << 'EOF' > /app/spectral-ode-sim-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    int steps = 1000;
    if (argc > 1) {
        steps = atoi(argv[1]);
    }
    double dt = 0.01;
    for (int i = 0; i < steps; i++) {
        double t = i * dt;
        double val = sin(2 * M_PI * 2.15 * t) + 0.1 * cos(2 * M_PI * 5.0 * t);
        printf("%f,%f\n", t, val);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/spectral-ode-sim-1.0/Makefile
all:
	gcc -O2 main.c -o ode_sim -m
EOF

    python3 -c "
import numpy as np
t = np.arange(0, 10, 0.01)
val = np.sin(2 * np.pi * 2.15 * t) + 0.2 * np.random.randn(len(t))
with open('/home/user/reference.csv', 'w') as f:
    for i in range(len(t)):
        f.write(f'{t[i]},{val[i]}\n')
"

    chmod -R 777 /home/user
    chmod -R 777 /app
