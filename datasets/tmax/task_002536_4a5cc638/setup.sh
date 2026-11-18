#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/signal_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <complex.h>

#define N 64
#define MC_ITERS 100000

int main() {
    double x[N];
    for (int i = 0; i < N; i++) {
        if (scanf("%lf", &x[i]) != 1) return 1;
    }

    double complex X[N];
    double magnitudes[N];
    double sum_mag = 0.0;

    // Standard DFT
    for (int k = 0; k < N; k++) {
        X[k] = 0;
        for (int n = 0; n < N; n++) {
            X[k] += x[n] * cexp(-I * 2.0 * M_PI * k * n / N);
        }
        magnitudes[k] = cabs(X[k]);
        sum_mag += magnitudes[k];
    }

    double P[N];
    for (int k = 0; k < N; k++) {
        P[k] = magnitudes[k] / sum_mag;
    }

    int seed = (int)(P[0] * 10000.0);
    srand(seed);

    int counts[N] = {0};
    for (int i = 0; i < MC_ITERS; i++) {
        int val = rand() % N;
        counts[val]++;
    }

    double Q[N];
    for (int k = 0; k < N; k++) {
        Q[k] = (double)counts[k] / MC_ITERS;
    }

    double tvd = 0.0;
    for (int k = 0; k < N; k++) {
        tvd += fabs(P[k] - Q[k]);
    }
    tvd *= 0.5;

    printf("%.6f\n", tvd);
    return 0;
}
EOF

    gcc -O2 /tmp/signal_processor.c -o /app/signal_processor -lm
    strip /app/signal_processor
    chmod +x /app/signal_processor
    rm /tmp/signal_processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
