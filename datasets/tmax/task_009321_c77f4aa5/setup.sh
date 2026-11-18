#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy scikit-learn pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
n = 1000
cat = np.random.choice(['X', 'Y'], n)

# Create 50 features
data = np.random.randn(n, 50)

# Add signal to category X for the first 5 features
data[cat == 'X', :5] += 0.8
data[cat == 'Y', :5] -= 0.8

# Add massive noise variance to feat_49 to ruin unscaled PCA
data[:, 49] *= 1000

df = pd.DataFrame(data, columns=[f'feat_{i}' for i in range(50)])
df['category'] = cat

df.to_parquet('/home/user/input_data.parquet')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
