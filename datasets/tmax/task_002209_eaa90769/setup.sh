#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng ffmpeg
    pip3 install pytest numpy scikit-learn

    mkdir -p /app/audio

    espeak-ng -w /app/audio/hparams_meeting.wav "Please configure the PCA step to use exactly four components, and set the random state to one zero four two."

    cat << 'EOF' > /app/oracle_etl.py
#!/usr/bin/env python3
import sys, json, re
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from itertools import product

def run_pipeline(file_path):
    with open(file_path, 'r') as f:
        data = json.load(f)

    bigrams_keys = [''.join(x) for x in product('abcdefghijklmnopqrstuvwxyz', repeat=2)]
    bigrams_idx = {b: i for i, b in enumerate(bigrams_keys)}

    X = np.zeros((len(data), 676))
    for i, text in enumerate(data):
        cleaned = re.sub(r'[^a-zA-Z]', '', text).lower()
        for j in range(len(cleaned)-1):
            bg = cleaned[j:j+2]
            if bg in bigrams_idx:
                X[i, bigrams_idx[bg]] += 1

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    pca = PCA(n_components=4, random_state=1042)
    X_pca = pca.fit_transform(X_scaled)

    for row in X_pca:
        print(','.join([f"{val:.4f}" for val in row]))

if __name__ == "__main__":
    run_pipeline(sys.argv[1])
EOF
    chmod +x /app/oracle_etl.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
