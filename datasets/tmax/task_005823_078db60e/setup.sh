#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn faiss-cpu

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import os

np.random.seed(42)
base = np.random.rand(4900, 512).astype(np.float32)
dupes = base[:100]
raw = np.vstack((base, dupes))

os.makedirs('/home/user', exist_ok=True)
np.save('/home/user/raw_embeddings.npy', raw)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
