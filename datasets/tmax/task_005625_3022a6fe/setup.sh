#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sum_sim.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <root>\n", argv[0]);
        return 1;
    }
    float r = atof(argv[1]);
    long long N = 1000000;

    float sum_fwd = 0.0f;
    for (long long i = 1; i <= N; i++) {
        float term = (float)((double)r / ((double)i * i + (double)r * r));
        sum_fwd += term;
    }

    float sum_bwd = 0.0f;
    for (long long i = N; i >= 1; i--) {
        float term = (float)((double)r / ((double)i * i + (double)r * r));
        sum_bwd += term;
    }

    printf("Forward: %.8f\n", sum_fwd);
    printf("Backward: %.8f\n", sum_bwd);
    return 0;
}
EOF

    chmod -R 777 /home/user
