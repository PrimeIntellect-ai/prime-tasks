#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn joblib

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 200

data = {
    'age': np.random.randint(20, 60, n_samples).astype(float),
    'training_score': np.random.uniform(40, 100, n_samples),
    'years_of_service': np.random.randint(1, 15, n_samples).astype(float),
    'department': np.random.choice(['Sales', 'Engineering', 'HR', 'Marketing'], n_samples),
    'education': np.random.choice(["Bachelor's", "Master's", "PhD"], n_samples),
    'is_promoted': np.random.binomial(1, 0.2, n_samples)
}

df = pd.DataFrame(data)

# Introduce some missing values
for col in ['age', 'training_score', 'department']:
    mask = np.random.rand(n_samples) < 0.1
    df.loc[mask, col] = np.nan

df.to_csv('/home/user/dataset.csv', index=False)
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
