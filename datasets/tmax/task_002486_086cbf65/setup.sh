#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /app/data /app/corpora/clean /app/corpora/evil /app/audio

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA

os.makedirs('/app/data', exist_ok=True)
np.random.seed(100)
X = np.random.rand(200, 10)
df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(10)])
df.to_csv('/app/data/raw_features.csv', index=False)

# Canonical pipeline
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)
pca = PCA(n_components=3, random_state=42)
X_canonical = pca.fit_transform(X_scaled)

# Create corpora directories
os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

# Generate Clean Corpus (Exact match or within 1e-5)
for i in range(20):
    noise = np.random.normal(0, 1e-6, X_canonical.shape)
    X_clean = X_canonical + noise
    pd.DataFrame(X_clean).to_csv(f'/app/corpora/clean/artifact_{i}.csv', index=False, header=False)

# Evil 1-5: No scaling
pca_bad = PCA(n_components=3, random_state=42)
X_bad1 = pca_bad.fit_transform(X)
for i in range(5):
    pd.DataFrame(X_bad1).to_csv(f'/app/corpora/evil/artifact_{i}.csv', index=False, header=False)

# Evil 6-10: Wrong seed
pca_bad2 = PCA(n_components=3, random_state=99)
X_bad2 = pca_bad2.fit_transform(X_scaled)
for i in range(5, 10):
    pd.DataFrame(X_bad2).to_csv(f'/app/corpora/evil/artifact_{i}.csv', index=False, header=False)

# Evil 11-15: Wrong components (4 instead of 3)
pca_bad3 = PCA(n_components=4, random_state=42)
X_bad3 = pca_bad3.fit_transform(X_scaled)
for i in range(10, 15):
    pd.DataFrame(X_bad3).to_csv(f'/app/corpora/evil/artifact_{i}.csv', index=False, header=False)

# Evil 16-20: Large noise
for i in range(15, 20):
    noise = np.random.normal(0, 1e-3, X_canonical.shape)
    X_bad4 = X_canonical + noise
    pd.DataFrame(X_bad4).to_csv(f'/app/corpora/evil/artifact_{i}.csv', index=False, header=False)
EOF

    python3 /tmp/setup.py

    espeak -w /app/audio/memo.wav "For the new pipeline, we load the raw features, apply standard scaling, and then run PCA with exactly three components. The random state must be set to forty-two for reproducibility."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
