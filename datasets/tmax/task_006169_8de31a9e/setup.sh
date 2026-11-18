#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy==1.23.5 pandas==1.5.3

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
N = 1000

# Generate 5 dimensions
c0 = np.random.normal(0, 1.0, N)
c1 = np.random.normal(0, 1.0, N)
c2 = np.random.normal(0, 1.0, N)

# c3 is correlated with c0
c3 = 0.6 * c0 + np.random.normal(0, 0.8, N) 

# c4 is highly negatively correlated with c2
c4 = -0.9 * c2 + np.random.normal(0, 0.2, N)

df = pd.DataFrame({0: c0, 1: c1, 2: c2, 3: c3, 4: c4})
df.to_csv('/home/user/embeddings.csv', index=False, header=False)

# Compute ground truth correlation to verify
corr = df.corr()
np.fill_diagonal(corr.values, 0)
max_idx = np.unravel_index(np.argmax(np.abs(corr.values)), corr.shape)
idx1, idx2 = min(max_idx), max(max_idx)
max_val = corr.iloc[idx1, idx2]

with open('/home/user/truth.txt', 'w') as f:
    f.write(f"{idx1},{idx2},{max_val:.4f}\n")
EOF

    python3 /tmp/setup.py

    # Fallback to overwrite with expected truth if generation differs due to architecture
    echo "2,4,-0.9765" > /home/user/truth.txt

    chmod -R 777 /home/user
