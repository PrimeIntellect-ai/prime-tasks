#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# Generate 500 base vectors, 64-dim
N = 500
D = 64
vectors = np.random.randn(N, D).astype(np.float32)
vectors /= np.linalg.norm(vectors, axis=1, keepdims=True)

# Inject exactly 15 duplicates (similarity > 0.95)
# We will make vector i+100 a near duplicate of vector i for i in range(15)
for i in range(15):
    noise = np.random.randn(D).astype(np.float32) * 0.05
    dup = vectors[i] + noise
    dup /= np.linalg.norm(dup)
    vectors[i+100] = dup

with open('/home/user/data/embeddings.bin', 'wb') as f:
    f.write(vectors.tobytes())
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/dedup.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 500
#define D 64

float cosine_sim(float* a, float* b) {
    float dot, norm_a, norm_b; // BUG: Uninitialized variables
    for(int i=0; i<D; i++) {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }
    return dot / (sqrt(norm_a) * sqrt(norm_b));
}

int main() {
    FILE *f = fopen("/home/user/data/embeddings.bin", "rb");
    if(!f) return 1;

    float* embeddings = malloc(N * D * sizeof(float));
    fread(embeddings, sizeof(float), N * D, f);
    fclose(f);

    int removed[N] = {0};
    int removed_count = 0;

    for(int i=0; i<N; i++) {
        if(removed[i]) continue;
        for(int j=i+1; j<N; j++) {
            if(removed[j]) continue;
            float sim = cosine_sim(&embeddings[i*D], &embeddings[j*D]);
            if(sim > 0.95) {
                removed[j] = 1;
                removed_count++;
            }
        }
    }

    printf("Removed Count: %d\n", removed_count);
    free(embeddings);
    return 0;
}
EOF

    chmod -R 777 /home/user
