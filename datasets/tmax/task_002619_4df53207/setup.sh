#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest pandas

    mkdir -p /home/user/ode
    cat << 'EOF' > /home/user/ode/simulator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s m k c t_end dt\n", argv[0]);
        return 1;
    }
    double m = atof(argv[1]);
    double k = atof(argv[2]);
    double c = atof(argv[3]);
    double t_end = atof(argv[4]);
    double dt = atof(argv[5]);

    double t = 0.0;
    double x = 1.0;
    double v = 0.0;

    while (t <= t_end + 1e-9) {
        printf("%.4f,%.6f,%.6f\n", t, x, v);
        double ax = (-k * x - c * v) / m;
        x += v * dt;
        v += ax * dt;
        t += dt;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/ode/baseline.py
import sys

if len(sys.argv) != 6:
    print("Usage: python3 baseline.py m k c t_end dt", file=sys.stderr)
    sys.exit(1)

m = float(sys.argv[1])
k = float(sys.argv[2])
c = float(sys.argv[3])
t_end = float(sys.argv[4])
dt = float(sys.argv[5])

t = 0.0
x = 1.0
v = 0.0

while t <= t_end + 1e-9:
    print(f"{t:.4f},{x:.6f},{v:.6f}")
    ax = (-k * x - c * v) / m
    x += v * dt
    v += ax * dt
    t += dt
EOF
    chmod +x /home/user/ode/baseline.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
