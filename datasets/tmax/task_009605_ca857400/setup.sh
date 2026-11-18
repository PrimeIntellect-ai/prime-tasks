#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/oscillator.c
#include <stdio.h>

int main() {
    double y = 1.0;
    double v = 0.0;
    double dt = 0.01;

    FILE *f = fopen("timeseries.csv", "w");

    // Unstable Euler method
    for (int i = 0; i <= 1000; i++) {
        double t = i * dt;
        fprintf(f, "%f,%f\n", t, y);

        double y_new = y + dt * v;
        double v_new = v + dt * (-100.0 * y - 2.0 * v);

        y = y_new;
        v = v_new;
    }

    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
