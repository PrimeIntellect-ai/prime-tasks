#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev binutils
    pip3 install pytest numpy scipy flask fastapi uvicorn requests

    mkdir -p /app
    cat << 'EOF' > /app/signal_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    double A = atof(argv[1]);
    double D = atof(argv[2]);
    double F = atof(argv[3]);

    for (int i = 0; i < 100; i++) {
        double t = i * 0.01;
        double val = A * exp(-t / D) * cos(2 * M_PI * F * t);
        printf("%f%s", val, i == 99 ? "" : ",");
    }
    printf("\n");
    return 0;
}
EOF
    gcc -O2 /app/signal_gen.c -o /app/signal_gen -lm
    strip -s /app/signal_gen
    rm /app/signal_gen.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
