#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas scipy statsmodels

    mkdir -p /home/user/network_sim/src
    mkdir -p /home/user/network_sim/data
    mkdir -p /home/user/network_sim/lib
    mkdir -p /home/user/network_sim/results

    cat << 'EOF' > /home/user/network_sim/src/diffusion.c
#include <stdlib.h>

// Computes the trace of the adjacency matrix squared 
// (number of self-returning walks of length 2)
double compute_diffusion(double* adj, int N) {
    double score = 0.0;
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            score += adj[i * N + j] * adj[j * N + i];
        }
    }
    return score;
}
EOF

    cat << 'EOF' > /home/user/network_sim/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
K, N = 100, 20
# Generate K graphs of size NxN
graphs = np.random.rand(K, N, N)
np.save('/home/user/network_sim/data/graphs.npy', graphs)

# Generate outcomes correlated with the diffusion score
# Diffusion score is approx N*N*E[X^2] ~ 400 * 0.333 ~ 133
scores = []
for k in range(K):
    adj = graphs[k]
    score = 0
    for i in range(N):
        for j in range(N):
            score += adj[i, j] * adj[j, i]
    scores.append(score)

scores = np.array(scores)
logits = -10 + 0.075 * scores
probs = 1 / (1 + np.exp(-logits))
outcomes = np.random.binomial(1, probs)

pd.DataFrame({'outcome': outcomes}).to_csv('/home/user/network_sim/data/outcomes.csv', index=False)
EOF

    python3 /home/user/network_sim/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
