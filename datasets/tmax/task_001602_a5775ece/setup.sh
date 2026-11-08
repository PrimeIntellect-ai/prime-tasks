#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy matplotlib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 20000
data = {
    'f1': np.random.randn(n_samples),
    'f2': np.random.randn(n_samples),
    'f3': np.random.randn(n_samples),
    'f4': np.random.randn(n_samples),
    'f5': np.random.randn(n_samples)
}
data['target'] = 3*data['f1'] + 1.5*data['f2'] - 2*data['f4'] + np.random.randn(n_samples)

df = pd.DataFrame(data)
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
