#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
D = 0.01
k = 0.1
sqrt_kd = np.sqrt(k/D)

def exact_C(x):
    return np.sinh(sqrt_kd * (1 - x)) / np.sinh(sqrt_kd)

xs = [0.2, 0.4, 0.6, 0.8]
means = [exact_C(x) for x in xs]
n_samples = 50

data = {}
for i, x in enumerate(xs):
    # Add some gaussian noise
    data[f'x_{x}'] = np.random.normal(loc=means[i], scale=0.05, size=n_samples)

df = pd.DataFrame(data)
df.to_csv('/home/user/protein_counts.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
