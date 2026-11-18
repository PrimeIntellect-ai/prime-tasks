#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/dataset

    # Create the C source for the legacy tool
    cat << 'EOF' > /app/encoder.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 11) {
        return 1;
    }
    float W[5][10] = {
        {0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0},
        {-0.5, 0.4, -0.3, 0.2, -0.1, 0.0, 0.1, -0.2, 0.3, -0.4},
        {1.1, -1.2, 1.3, -1.4, 1.5, -1.6, 1.7, -1.8, 1.9, -2.0},
        {0.0, 0.0, 1.0, 1.0, 0.0, 0.0, -1.0, -1.0, 0.5, -0.5},
        {0.33, 0.66, 0.99, -0.33, -0.66, -0.99, 0.5, 0.25, -0.5, -0.25}
    };
    float x[10];
    for (int i = 0; i < 10; i++) {
        x[i] = atof(argv[i+1]);
    }
    for (int i = 0; i < 5; i++) {
        float y = 0;
        for (int j = 0; j < 10; j++) {
            y += W[i][j] * x[j];
        }
        printf("%.6f", y);
        if (i < 4) printf(" ");
    }
    printf("\n");
    return 0;
}
EOF

    # Compile the legacy tool and strip it
    gcc -O2 -s -o /app/sensor_encoder /app/encoder.c
    rm /app/encoder.c

    # Generate the datasets
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
raw_candidates = np.random.randn(5000, 10).astype(np.float32)
np.save('/home/user/dataset/raw_candidates.npy', raw_candidates)

W = np.array([
    [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
    [-0.5, 0.4, -0.3, 0.2, -0.1, 0.0, 0.1, -0.2, 0.3, -0.4],
    [1.1, -1.2, 1.3, -1.4, 1.5, -1.6, 1.7, -1.8, 1.9, -2.0],
    [0.0, 0.0, 1.0, 1.0, 0.0, 0.0, -1.0, -1.0, 0.5, -0.5],
    [0.33, 0.66, 0.99, -0.33, -0.66, -0.99, 0.5, 0.25, -0.5, -0.25]
], dtype=np.float32)

subset = raw_candidates[:1000]
clean_embeddings = subset.dot(W.T)
noise = np.random.normal(0, 2.5, clean_embeddings.shape).astype(np.float32)
corrupted_embeddings = clean_embeddings + noise

df = pd.DataFrame(corrupted_embeddings)
df.to_csv('/home/user/dataset/corrupted_embeddings.csv', index=False, header=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
