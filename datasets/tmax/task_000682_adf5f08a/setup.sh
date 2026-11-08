#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    # Create the Python script to generate reproducible data
    cat << 'EOF' > generate_data.py
import numpy as np

np.random.seed(42)
# 1000 vectors of 128 floats
embeddings = np.random.randn(1000, 128).astype(np.float32)
# query vector is similar to vector 42
query = embeddings[42] + np.random.randn(128).astype(np.float32) * 0.1

embeddings.tofile("/home/user/embeddings.bin")
query.tofile("/home/user/query.bin")

# Compute truth
from numpy.linalg import norm
sims = []
for i, emb in enumerate(embeddings):
    sim = np.dot(query, emb) / (norm(query) * norm(emb))
    sims.append((i, sim))

sims.sort(key=lambda x: x[1], reverse=True)
with open("/home/user/truth_top5.txt", "w") as f:
    for i in range(5):
        f.write(f"{sims[i][0]}\n")
EOF

    python3 generate_data.py

    # Create the buggy C program
    cat << 'EOF' > /home/user/sim_search.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define DIM 128

void compute_similarity(float *query, float *dataset, int num_vectors, float *scores) {
    for (int i = 0; i < num_vectors; i++) {
        int dot = 0; // BUG: Should be float
        float norm_q = 0.0;
        float norm_d = 0.0;
        for (int j = 0; j < DIM; j++) {
            dot += query[j] * dataset[i * DIM + j];
            norm_q += query[j] * query[j];
            norm_d += dataset[i * DIM + j] * dataset[i * DIM + j];
        }
        scores[i] = (float)dot / (sqrt(norm_q) * sqrt(norm_d));
    }
}

int main() {
    FILE *fq = fopen("/home/user/query.bin", "rb");
    if (!fq) return 1;
    float query[DIM];
    fread(query, sizeof(float), DIM, fq);
    fclose(fq);

    FILE *fd = fopen("/home/user/embeddings.bin", "rb");
    if (!fd) return 1;
    fseek(fd, 0, SEEK_END);
    long file_size = ftell(fd);
    fseek(fd, 0, SEEK_SET);

    int num_vectors = file_size / (DIM * sizeof(float));
    float *dataset = malloc(file_size);
    fread(dataset, sizeof(float), DIM * num_vectors, fd);
    fclose(fd);

    float *scores = malloc(num_vectors * sizeof(float));
    compute_similarity(query, dataset, num_vectors, scores);

    for (int i = 0; i < num_vectors; i++) {
        printf("%d %f\n", i, scores[i]);
    }

    free(dataset);
    free(scores);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
