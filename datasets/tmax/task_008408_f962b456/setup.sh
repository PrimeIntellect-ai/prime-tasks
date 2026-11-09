#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import math
import os

os.makedirs('/home/user/artifacts', exist_ok=True)

# Generate deterministic data to establish a ground truth correlation
N = 1000
emb1 = [float(i) for i in range(N)]
emb2 = [float(i * i) for i in range(N)]

with open('/home/user/artifacts/emb1.bin', 'wb') as f1:
    f1.write(struct.pack(f'{N}f', *emb1))

with open('/home/user/artifacts/emb2.bin', 'wb') as f2:
    f2.write(struct.pack(f'{N}f', *emb2))

# Calculate ground truth correlation to verify later
mean1 = sum(emb1) / N
mean2 = sum(emb2) / N

num = sum((x - mean1) * (y - mean2) for x, y in zip(emb1, emb2))
den = math.sqrt(sum((x - mean1)**2 for x in emb1) * sum((y - mean2)**2 for y in emb2))
corr = num / den

with open('/home/user/ground_truth.txt', 'w') as f:
    f.write(f"{corr:.4f}\n")

# Write the C skeleton
c_code = """#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Function to implement
float compute_pearson(float* x, float* y, int n) {
    // TODO: Implement Pearson correlation coefficient
    return 0.0;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        printf("Usage: %s <file1> <file2> <n>\\n", argv[0]);
        return 1;
    }

    int n = atoi(argv[3]);
    float *x = malloc(n * sizeof(float));
    float *y = malloc(n * sizeof(float));

    FILE *f1 = fopen(argv[1], "rb");
    FILE *f2 = fopen(argv[2], "rb");
    if (!f1 || !f2) {
        printf("Error opening files.\\n");
        return 1;
    }

    fread(x, sizeof(float), n, f1);
    fread(y, sizeof(float), n, f2);
    fclose(f1); 
    fclose(f2);

    float corr = compute_pearson(x, y, n);
    printf("%.4f\\n", corr);

    free(x); 
    free(y);
    return 0;
}
"""

with open('/home/user/calc_corr.c', 'w') as f:
    f.write(c_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
