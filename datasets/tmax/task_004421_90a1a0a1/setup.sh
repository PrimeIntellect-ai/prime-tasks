#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/datasets', exist_ok=True)
np.random.seed(42)

def create_dataset(filename, noise_level):
    n_samples = 200
    f1 = np.random.randn(n_samples) * 5
    f2 = np.random.randn(n_samples) * 10
    f3 = np.random.randn(n_samples) * 2

    # Target is a linear combination
    target = 3.5 * f1 - 1.2 * f2 + 0.5 * f3 + np.random.randn(n_samples) * noise_level

    df = pd.DataFrame({'feature1': f1, 'feature2': f2, 'feature3': f3, 'target': target})

    # Introduce missing values
    for col in ['feature1', 'feature2', 'feature3']:
        missing_idx = np.random.choice(n_samples, size=int(n_samples * 0.1), replace=False)
        df.loc[missing_idx, col] = np.nan

    # Introduce outliers in target
    outlier_idx_high = np.random.choice(n_samples, size=3, replace=False)
    outlier_idx_low = np.random.choice(n_samples, size=3, replace=False)
    df.loc[outlier_idx_high, 'target'] += 500
    df.loc[outlier_idx_low, 'target'] -= 500

    df.to_csv(f'/home/user/datasets/{filename}', index=False)

create_dataset('data_A.csv', 1.0)
create_dataset('data_B.csv', 5.0)
create_dataset('data_C.csv', 10.0)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
