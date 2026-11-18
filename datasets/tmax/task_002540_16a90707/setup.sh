#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/mlops

    cat << 'EOF' > /home/user/mlops/kernel.h
#ifndef KERNEL_H
#define KERNEL_H

void kernel_infer(const float* weights, const float* inputs, float* outputs, int n);

#endif
EOF

    cat << 'EOF' > /home/user/mlops/kernel.c
#include "kernel.h"

// A simple unrolled matrix-vector multiplication simulation
void kernel_infer(const float* weights, const float* inputs, float* outputs, int n) {
    for (int i = 0; i < n; i++) {
        float sum = 0.0f;
        int row_offset = i * n;
        // manually unroll slightly for the illusion of an "optimized" kernel
        int j = 0;
        for (; j <= n - 4; j += 4) {
            sum += weights[row_offset + j] * inputs[j];
            sum += weights[row_offset + j + 1] * inputs[j + 1];
            sum += weights[row_offset + j + 2] * inputs[j + 2];
            sum += weights[row_offset + j + 3] * inputs[j + 3];
        }
        for (; j < n; j++) {
            sum += weights[row_offset + j] * inputs[j];
        }
        outputs[i] = sum;
    }
}
EOF

    chmod +x /home/user/mlops/kernel.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
