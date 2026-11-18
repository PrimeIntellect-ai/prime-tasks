#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

df = pd.DataFrame({
    'X1': [10, 12, np.nan, 14, 11, 13, 10, 15, 11, 12],
    'X2': [0.5, 0.6, 0.55, 0.4, np.nan, 0.65, 0.52, 0.7, 0.58, 0.55],
    'X3': [100, 110, 105, 1000, 90, 115, 102, 98, 105, 108]
})

df_csv = df.copy()
df_csv['X1'] = df_csv['X1'].apply(lambda x: 'MISSING' if pd.isna(x) else str(int(x)))
df_csv['X2'] = df_csv['X2'].apply(lambda x: 'MISSING' if pd.isna(x) else str(x))
df_csv['X3'] = df_csv['X3'].apply(lambda x: str(int(x)))

df_csv.to_csv('/home/user/dataset.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
