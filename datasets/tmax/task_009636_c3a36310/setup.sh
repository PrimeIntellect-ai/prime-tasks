#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/graph.txt
1 2
2 3
3 4
4 1
1 3
EOF

    cat << 'EOF' > /home/user/sim/network_mc.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <math.h>

int main() {
    // Read graph (dummy read for the sake of the scenario)
    FILE *f = fopen("/home/user/sim/graph.txt", "r");
    if (!f) return 1;
    int u, v;
    while(fscanf(f, "%d %d", &u, &v) == 2) {}
    fclose(f);

    srand(42); // Fixed seed
    int n_steps = 500000;
    float total_score = 0.0f;

    // OpenMP parallel loop with atomic addition to force non-deterministic floating-point rounding
    #pragma omp parallel for
    for(int i=0; i<n_steps; i++) {
        float val = sin((float)i) * cos((float)i);
        if (val < 0) val = -val;

        #pragma omp atomic
        total_score += val;
    }

    printf("Final Score: %.6f\n", total_score);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
