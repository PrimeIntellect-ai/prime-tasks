#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os
from scipy.integrate import odeint

# Set random seed for reproducibility
np.random.seed(42)

# True parameters
strains = {
    'Strain_Alpha': {'r': 0.65, 'K': 1.20, 'y0': 0.05, 'seq': 'ATGCGTACGTAGCTAGCTAGCATCGATCGATCGA'},
    'Strain_Beta':  {'r': 0.40, 'K': 0.85, 'y0': 0.10, 'seq': 'GCATCGATCGATCGTACGTAGCTAGCTAGCATCG'},
    'Strain_Gamma': {'r': 0.90, 'K': 1.60, 'y0': 0.02, 'seq': 'CGATCGATCGATCGATCGATCGATCGATCGATCG'}
}

# Create FASTA
with open('/home/user/strains.fasta', 'w') as f:
    for s_id, data in strains.items():
        f.write(f">{s_id}\n{data['seq']}\n")

# Create Growth Data
times = np.linspace(0, 10, 21)
records = []

def logistic_deriv(y, t, r, K):
    return r * y * (1 - y / K)

for s_id, data in strains.items():
    # Solve ODE to get true curve
    y_true = odeint(logistic_deriv, data['y0'], times, args=(data['r'], data['K'])).flatten()

    # Add noise (Gaussian, sigma=0.04)
    y_noisy = y_true + np.random.normal(0, 0.04, size=len(times))
    # Ensure no negative OD600 values
    y_noisy = np.maximum(y_noisy, 0.001)

    for t, y in zip(times, y_noisy):
        records.append({'StrainID': s_id, 'Time': t, 'OD600': y})

df = pd.DataFrame(records)
df.to_csv('/home/user/growth_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
