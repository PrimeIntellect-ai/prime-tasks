#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
n_samples_1 = 300
n_samples_2 = 200
n_features = 50

# Base frequencies
base_freqs = np.random.uniform(0.01, 0.05, n_features)

# Motif 1 (adds to sub-pop 1)
motif_1 = np.zeros(n_features)
motif_1[5:15] = 0.08

# Motif 2 (adds to sub-pop 2)
motif_2 = np.zeros(n_features)
motif_2[30:40] = 0.06

X1 = np.random.poisson((base_freqs + motif_1) * 1000, (n_samples_1, n_features))
X2 = np.random.poisson((base_freqs + motif_2) * 1000, (n_samples_2, n_features))

X = np.vstack([X1, X2]).astype(float)
# Add some noise
X += np.random.normal(0, 5, X.shape)

df = pd.DataFrame(X, columns=[f"kmer_{i}" for i in range(n_features)])
df.to_csv("/home/user/kmer_frequencies.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
