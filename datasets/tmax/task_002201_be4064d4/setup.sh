#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data_gen.c
#include <stdio.h>
#include <math.h>

float compute_feature(int i, int j) {
    float dt = 0.001f;
    float y = (float)(i + j + 1);
    float sum = 0.0f;
    // Naive Euler integration with naive summation
    for(int step=0; step<100000; step++) {
        float dy = -0.01f * y * dt;
        y += dy;
        sum += y * dt;
    }
    return sum;
}

int main() {
    FILE *f = fopen("/home/user/matrix.txt", "w");
    if (!f) return 1;
    for(int i=0; i<10; i++) {
        for(int j=0; j<10; j++) {
            fprintf(f, "%f ", compute_feature(i, j));
        }
        fprintf(f, "\n");
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
