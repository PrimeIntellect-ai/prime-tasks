#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 5000
w_true = 0.85
mu1_true, sigma1_true = 45.0, 8.0
mu2_true, sigma2_true = 210.0, 40.0

n1 = int(n_samples * w_true)
n2 = n_samples - n1

data1 = np.random.normal(mu1_true, sigma1_true, n1)
data2 = np.random.normal(mu2_true, sigma2_true, n2)
data = np.concatenate([data1, data2])
np.random.shuffle(data)

df = pd.DataFrame({'latency_ms': data})
df.to_csv('/home/user/latencies.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
