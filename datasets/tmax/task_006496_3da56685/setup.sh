#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow fastparquet

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
n_rows = 50000

ids = np.arange(1, n_rows + 1)
timestamps = pd.date_range(start='2023-01-01', periods=n_rows, freq='S')

df_alpha = pd.DataFrame({
    'id': ids,
    'timestamp': timestamps,
    'x_coord': np.random.uniform(-100, 100, n_rows),
    'y_coord': np.random.uniform(-100, 100, n_rows),
    'z_coord': np.random.uniform(-100, 100, n_rows)
})

df_alpha = df_alpha.sample(frac=1).reset_index(drop=True)

df_beta = pd.DataFrame({
    'id': ids,
    'timestamp': timestamps,
    'temperature': np.random.uniform(20, 100, n_rows),
    'pressure': np.random.uniform(900, 1100, n_rows)
})

df_beta = df_beta.sample(frac=1).reset_index(drop=True)

os.makedirs('/home/user', exist_ok=True)
df_alpha.to_csv('/home/user/sensor_alpha.csv', index=False)
df_beta.to_csv('/home/user/sensor_beta.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
