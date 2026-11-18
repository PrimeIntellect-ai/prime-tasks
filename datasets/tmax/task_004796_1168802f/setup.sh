#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import h5py
import numpy as np
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# Generate synthetic embeddings
corpus = np.random.randn(10000, 128).astype(np.float32)
queries = np.random.randn(50, 128).astype(np.float32)

with h5py.File('/home/user/data/embeddings.h5', 'w') as f:
    f.create_dataset('corpus', data=corpus)
    f.create_dataset('queries', data=queries)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
