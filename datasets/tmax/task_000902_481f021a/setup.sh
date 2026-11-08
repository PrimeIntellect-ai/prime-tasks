#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

n = 1000
value_1 = np.random.normal(50, 10, n)
value_1[np.random.choice(n, 50, replace=False)] = np.nan

value_2 = np.random.normal(100, 20, n)
value_2[np.random.choice(n, 10, replace=False)] = 5000  # outliers
value_2[np.random.choice(n, 10, replace=False)] = -5000 # outliers

texts = [" ".join(["word"] * np.random.randint(1, 20)) for _ in range(n)]

# Calculate correct cleaned values to generate target
v1_clean = np.where(np.isnan(value_1), np.nanmedian(value_1), value_1)
v2_clean = np.clip(value_2, np.percentile(value_2, 5), np.percentile(value_2, 95))
seq_len = np.array([len(t.split()) for t in texts])

target = 2.5 * v1_clean + 1.2 * v2_clean + seq_len * 5 + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'id': range(n),
    'text': texts,
    'value_1': value_1,
    'value_2': value_2,
    'target': target
})
df.to_csv('/home/user/data/raw_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
