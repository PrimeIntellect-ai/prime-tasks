#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
data = np.random.randn(500, 50)
# Create some strong variance for PC1 so it's dominant and stable
data[:, :10] += np.random.randn(500, 1) * 3 

df = pd.DataFrame(data, columns=[f'f{i+1}' for i in range(50)])
# Mess up f1 by introducing NaNs
df['f1'] = np.random.randint(0, 10, size=500).astype(float)
df.loc[np.random.choice(500, 25, replace=False), 'f1'] = np.nan

df.to_csv('/home/user/dataset.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
