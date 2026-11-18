#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/density_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <omp.h>

#define N 100000

double compute_node_weight(int i) {
    // Simulated heavy density calculation for a node
    return sin(i) * sin(i) + cos(i / 2.0);
}

int main() {
    double total_density = 0.0;

    #pragma omp parallel for num_threads(4)
    for(int i = 0; i < N; i++) {
        double w = compute_node_weight(i);
        #pragma omp atomic
        total_density += w;
    }

    printf("%.10f\n", total_density);
    return 0;
}
EOF

    chmod -R 777 /home/user
