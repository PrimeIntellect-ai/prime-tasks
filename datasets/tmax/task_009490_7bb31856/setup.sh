#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

# Set random seed for reproducibility
np.random.seed(42)

N_total = 50000
D = 10

# Generate reference vector
ref_vector = np.random.randn(D).astype(np.float32)
# Normalize reference vector
ref_vector /= np.linalg.norm(ref_vector)

# Generate base embeddings
embeddings = np.random.randn(N_total, D).astype(np.float32)

# Make a subset explicitly similar to the reference vector
# We'll modify about 1200 vectors to be very close to the reference
num_similar = 1200
similar_indices = np.random.choice(N_total, num_similar, replace=False)
for idx in similar_indices:
    noise = np.random.randn(D).astype(np.float32) * 0.2
    vec = ref_vector + noise
    embeddings[idx] = vec

# Save files
embeddings.tofile('/home/user/embeddings.bin')
np.savetxt('/home/user/ref_vector.txt', ref_vector.reshape(1, -1), fmt='%.6f', delimiter=' ')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
