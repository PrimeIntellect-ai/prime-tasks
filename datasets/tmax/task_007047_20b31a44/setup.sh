#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
control = np.random.normal(loc=150, scale=20, size=500)
treatment = np.random.normal(loc=145, scale=22, size=500)

df = pd.DataFrame({
    'group': ['control']*500 + ['treatment']*500,
    'latency': np.concatenate([control, treatment])
})
df.to_csv('/home/user/server_metrics.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
