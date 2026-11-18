#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn h5py tables numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data_chunks', exist_ok=True)

# Generate synthetic dataset
np.random.seed(123) # Different seed for generation
X = np.random.randn(1000, 4)
y = 3.5 * X[:, 0] - 2.0 * X[:, 1] + 0.5 * X[:, 2] + np.random.randn(1000) * 0.5

df = pd.DataFrame(X, columns=['f1', 'f2', 'f3', 'f4'])
df['target'] = y

# Split into 5 chunks
chunk_size = 200
for i in range(5):
    chunk = df.iloc[i*chunk_size : (i+1)*chunk_size]
    chunk.to_csv(f'/home/user/data_chunks/chunk_{i}.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
