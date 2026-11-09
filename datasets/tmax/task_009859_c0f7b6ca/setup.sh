#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/profiler.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int trials = atoi(argv[1]);

    // Hardcoded deterministic "performance" output for stable automated testing
    // Row 1: 1 thread, Row 2: 2 threads, Row 3: 4 threads, Row 4: 8 threads
    float data[4][5] = {
        {10.0, 10.2, 9.8, 10.1, 9.9},
        {5.5, 5.6, 5.4, 5.5, 5.5},
        {3.0, 3.1, 2.9, 3.0, 3.0},
        {2.0, 2.1, 1.9, 2.0, 2.0}
    };

    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < trials && j < 5; j++) {
            printf("%.1f ", data[i][j]);
        }
        printf("\n");
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
