#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/thermal_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double f(double t) {
    return exp(-t) * sin(t);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    double x = atof(argv[1]);
    if (x <= 0) {
        printf("0.000000\n");
        return 0;
    }
    int n = 1000;
    double h = x / n;
    double sum = 0.5 * (f(0) + f(x));
    for (int i = 1; i < n; i++) {
        sum += f(i * h);
    }
    printf("%.8f\n", sum * h);
    return 0;
}
EOF
    chmod 644 /home/user/thermal_sim.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
