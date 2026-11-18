#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/process_spectroscopy.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define SIZE 500

void apply_filter(float *input, float *output) {
    // Naive 2D smoothing filter (intentionally unoptimized to be the bottleneck)
    for (int i = 1; i < SIZE - 1; i++) {
        for (int j = 1; j < SIZE - 1; j++) {
            float sum = 0;
            for (int di = -1; di <= 1; di++) {
                for (int dj = -1; dj <= 1; dj++) {
                    sum += input[(i + di) * SIZE + (j + dj)];
                }
            }
            output[i * SIZE + j] = sum / 9.0;
        }
    }
}

void add_noise(float *data) {
    // Secondary function, takes less time
    for(int i = 0; i < SIZE * SIZE; i++) {
        data[i] += 0.0001 * (rand() % 100);
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <input> <output>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    FILE *fout = fopen(argv[2], "wb");
    if(!fin || !fout) return 1;

    float *input = calloc(SIZE * SIZE, sizeof(float));
    float *output = calloc(SIZE * SIZE, sizeof(float));

    fread(input, sizeof(float), SIZE * SIZE, fin);

    add_noise(input);
    apply_filter(input, output);

    fwrite(output, sizeof(float), SIZE * SIZE, fout);

    fclose(fin);
    fclose(fout);
    free(input);
    free(output);
    return 0;
}
EOF

    python3 -c '
import numpy as np
size = 500
Z = np.zeros((size, size), dtype=np.float32)
# Add a strong signal at frequency (row=15, col=25)
for r in range(size):
    for c in range(size):
        Z[r, c] = np.sin(2 * np.pi * (15 * r / size + 25 * c / size))
Z.tofile("/home/user/input.dat")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
