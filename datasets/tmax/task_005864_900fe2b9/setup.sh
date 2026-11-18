#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/workload.c
#include <stdio.h>
#include <omp.h>
#include <math.h>

int main() {
    double results[100];
    omp_set_num_threads(4);
    #pragma omp parallel for
    for(int i=0; i<100; i++) {
        results[i] = 100.0 + 10.0 * sin(i) + (i % 3);
    }
    for(int i=0; i<100; i++) {
        printf("%.4f\n", results[i]);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
