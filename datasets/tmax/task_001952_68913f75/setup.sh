#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc binutils
    pip3 install pytest requests

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    if (argc != 5) return 1;
    double y1 = atof(argv[1]);
    double y2 = atof(argv[2]);
    double y3 = atof(argv[3]);
    double t_end = atof(argv[4]);

    double t = 0;
    double dt = 1e-6; // very small step for reference
    while (t < t_end) {
        if (t + dt > t_end) dt = t_end - t;
        double dy1 = -0.04 * y1 + 10000.0 * y2 * y3;
        double dy2 = 0.04 * y1 - 10000.0 * y2 * y3 - 30000000.0 * y2 * y2;
        double dy3 = 30000000.0 * y2 * y2;
        y1 += dy1 * dt;
        y2 += dy2 * dt;
        y3 += dy3 * dt;
        t += dt;
    }
    printf("%.7g %.7g %.7g\n", y1, y2, y3);
    return 0;
}
EOF

    gcc -O3 /app/oracle.c -o /app/chemical_oracle
    strip /app/chemical_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
