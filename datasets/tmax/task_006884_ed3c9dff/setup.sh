#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy emcee

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
t = np.linspace(0, 5, 100)
a_true = 0.5
b_true = 3.14159
y_true = np.exp(-a_true * t) * np.cos(b_true * t)
noise = np.random.normal(0, 0.1, size=len(t))
y_noisy = y_true + noise

df = pd.DataFrame({'t': t, 'y': y_noisy})
df.to_csv('/home/user/noisy_data.csv', index=False)
EOF

    python3 /home/user/generate_setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
