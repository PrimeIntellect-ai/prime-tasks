#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/signal_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main() {
    size_t n = 10000000;
    double *data = malloc(n * sizeof(double));
    if (!data) return 1;

    // Simulate nanopore signal data
    for(size_t i = 0; i < n; i++) {
        data[i] = (double)(i % 100) / 100.0;
    }

    double total_power = 0.0;

    // BUG: Data race in accumulation
    #pragma omp parallel for
    for(size_t i = 0; i < n; i++) {
        double filtered = data[i] * 0.95; // apply scaling filter
        total_power += filtered;          // race condition here!
    }

    printf("%.6f\n", total_power);

    free(data);
    return 0;
}
EOF

    chmod 644 /home/user/signal_processor.c
    chmod -R 777 /home/user
