#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/experiments', exist_ok=True)

np.random.seed(123)

# Helper to generate data
def make_df(n_rows, model_name, bad_conf=False):
    df = pd.DataFrame({
        'id': range(n_rows),
        'model_name': [model_name] * n_rows,
        'prediction': np.random.uniform(0, 100, n_rows),
        'confidence': np.random.uniform(0.1, 0.9, n_rows)
    })
    if bad_conf:
        # Introduce invalid confidence
        df.loc[n_rows // 2, 'confidence'] = 1.5
    return df

# File 1: Valid and large (>50KB implies ~1500+ rows typically, we'll use 3000)
df1 = make_df(3000, 'model_A')
df1.to_csv('/home/user/experiments/run_A.csv', index=False)

# File 2: Invalid (contains confidence = 1.5) and large
df2 = make_df(3000, 'model_B', bad_conf=True)
df2.to_csv('/home/user/experiments/run_B.csv', index=False)

# File 3: Valid and large
df3 = make_df(3000, 'model_C')
df3.to_csv('/home/user/experiments/run_C.csv', index=False)

# File 4: Valid but small (<50KB, 50 rows is ~2KB)
df4 = make_df(50, 'model_D')
df4.to_csv('/home/user/experiments/run_D.csv', index=False)

# Calculate ground truth based on rules
# Valid and >= 50KB: run_A.csv and run_C.csv
combined = pd.concat([df1, df3], ignore_index=True)
sample = combined['prediction'].sample(n=1000, replace=True, random_state=42)
expected_mean = round(sample.mean(), 4)

with open('/home/user/.expected_truth', 'w') as f:
    f.write(f"{expected_mean:.4f}")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
