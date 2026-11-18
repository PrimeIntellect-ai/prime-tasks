#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import time

# 1. Generate dirty_embeddings.npy
np.random.seed(10)
# Base vectors
base = np.random.randn(1500, 32).astype(np.float32)
# Normalize base
base = base / np.linalg.norm(base, axis=1, keepdims=True)

# Generate duplicates by adding tiny noise to random base vectors
duplicates = []
for _ in range(500):
    idx = np.random.randint(0, 1500)
    noise = np.random.randn(32) * 0.05
    vec = base[idx] + noise
    vec = vec / np.linalg.norm(vec)
    duplicates.append(vec)

duplicates = np.array(duplicates, dtype=np.float32)

dirty_embeddings = np.vstack((base, duplicates))
np.random.shuffle(dirty_embeddings) # shuffle to mix them up
np.save('/home/user/dirty_embeddings.npy', dirty_embeddings)

# 2. Create inference_api.py
api_code = """
import time
import numpy as np

def infer_model_alpha(vector):
    # Simulate an inference time with mean ~10ms and some variance
    delay = np.random.normal(0.010, 0.002)
    delay = max(0.001, delay)
    time.sleep(delay)
    return np.sum(vector)

def infer_model_beta(vector):
    # Simulate an inference time with mean ~12ms and some variance
    delay = np.random.normal(0.012, 0.002)
    delay = max(0.001, delay)
    time.sleep(delay)
    return np.sum(vector)
"""

with open('/home/user/inference_api.py', 'w') as f:
    f.write(api_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
