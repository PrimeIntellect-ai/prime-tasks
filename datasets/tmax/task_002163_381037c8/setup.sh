#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas matplotlib emcee

    mkdir -p /home/user/data /home/user/results

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)

T = np.linspace(40, 90, 51)
L_true = 10.0
U_true = 100.0
k_true = 0.5
Tm_true = 68.5

# Sigmoid function
F = L_true + (U_true - L_true) / (1.0 + np.exp(-k_true * (T - Tm_true)))

# Add noise
noise = np.random.normal(0, 2.5, size=T.shape)
F_noisy = F + noise

df = pd.DataFrame({'Temperature': T, 'Fluorescence': F_noisy})
df.to_csv('/home/user/data/melting_curve.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
