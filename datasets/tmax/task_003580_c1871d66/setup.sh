#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/tensor_ops.c
#include <stdlib.h>

void compute_interactions(double* A, int N) {
    // Dummy O(N^3) operation to simulate heavy tensor interaction
    volatile double sum = 0;
    for(int i=0; i<N; i++) {
        for(int j=0; j<N; j++) {
            for(int k=0; k<N; k++) {
                sum += A[i*N + j] * A[j*N + k];
            }
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
