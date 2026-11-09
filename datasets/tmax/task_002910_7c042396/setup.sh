#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs("/home/user/experiments", exist_ok=True)
np.random.seed(123) # Seed for data generation

for i in range(1, 11):
    n_samples = 250
    true_label = np.random.randint(0, 2, n_samples)

    # Runs 02, 05, 09 are corrupted
    is_corrupted = i in [2, 5, 9]

    if is_corrupted:
        text_token_id = np.random.randint(1, 1000, n_samples).astype(float)
        # Introduce NaNs
        nan_indices = np.random.choice(n_samples, 15, replace=False)
        text_token_id[nan_indices] = np.nan
        # Corrupted predictions: lower correlation (mostly random noise)
        predicted_prob = true_label * 0.1 + np.random.rand(n_samples) * 0.9
    else:
        text_token_id = np.random.randint(1, 1000, n_samples) # Ints
        # Clean predictions: higher correlation
        predicted_prob = true_label * 0.6 + np.random.rand(n_samples) * 0.4

    df = pd.DataFrame({
        "sample_id": range(n_samples),
        "text_token_id": text_token_id,
        "true_label": true_label,
        "predicted_prob": predicted_prob,
        "model_version": f"v1.{i}"
    })

    df.to_csv(f"/home/user/experiments/run_{i:02d}.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
