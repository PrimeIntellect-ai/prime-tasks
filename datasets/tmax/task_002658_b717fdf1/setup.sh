#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate base data
n_rows = 1000
cols = ['alpha', 'beta', 'gamma', 'delta', 'epsilon']
base_data = pd.DataFrame(np.random.randn(n_rows, 5), columns=cols)

# run1 is exactly the base data
base_data.to_csv('run1_output.csv', index=False)

# Generate noise
noise_alpha = np.random.randn(n_rows) * 1e-6
noise_gamma = np.random.randn(n_rows) * 1e-6
noise_epsilon = np.random.randn(n_rows) * 1e-6

# Correlated noise for beta and delta
shared_noise = np.random.randn(n_rows) * 1e-4
noise_beta = shared_noise + np.random.randn(n_rows) * 1e-5
noise_delta = shared_noise + np.random.randn(n_rows) * 1e-5

noise_df = pd.DataFrame({
    'alpha': noise_alpha,
    'beta': noise_beta,
    'gamma': noise_gamma,
    'delta': noise_delta,
    'epsilon': noise_epsilon
})

# run2 has noise
run2_data = base_data + noise_df
run2_data.to_csv('run2_output.csv', index=False)
EOF

    python3 setup_data.py
    rm setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
