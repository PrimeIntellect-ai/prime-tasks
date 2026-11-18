#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Use a fixed seed for reproducible dataset generation
np.random.seed(42)

data = []
# Baseline
for i in range(30):
    data.append({'run_id': f'base_{i}', 'num_layers': 2, 'hidden_size': 64, 'accuracy': np.random.normal(0.82, 0.05)})

# Config A (Best)
for i in range(30):
    data.append({'run_id': f'A_{i}', 'num_layers': 3, 'hidden_size': 128, 'accuracy': np.random.normal(0.85, 0.04)})

# Config B
for i in range(30):
    data.append({'run_id': f'B_{i}', 'num_layers': 4, 'hidden_size': 256, 'accuracy': np.random.normal(0.80, 0.06)})

df = pd.DataFrame(data)
df.to_csv('/home/user/experiments.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
