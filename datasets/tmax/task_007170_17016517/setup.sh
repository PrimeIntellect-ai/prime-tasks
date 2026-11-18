#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_data.py
import os
import pandas as pd
import numpy as np

np.random.seed(42)
n_rows = 500

data = {f"sensor_{i}": np.random.randn(n_rows) * (i+1) for i in range(1, 11)}
df = pd.DataFrame(data)

# Create machine_id with integers 1-5
df['machine_id'] = np.random.randint(1, 6, size=n_rows).astype(object)

# Introduce a NaN to force silent float conversion if read naively
df.loc[150, 'machine_id'] = np.nan

# Target
df['is_faulty'] = np.random.randint(0, 2, size=n_rows)

df.to_csv("/home/user/sensor_data.csv", index=False)
EOF

    python3 /tmp/create_data.py
    rm /tmp/create_data.py

    chmod -R 777 /home/user
