#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

np.random.seed(42)
# Create a dataset with an intrinsic dimensionality of ~8
latent_dim = 8
n_features = 50
n_train = 1000
n_test = 10000

# Generate latent space
train_latent = np.random.randn(n_train, latent_dim) * np.array([10, 8, 6, 5, 4, 3, 2, 1])
test_latent = np.random.randn(n_test, latent_dim) * np.array([10, 8, 6, 5, 4, 3, 2, 1])

# Transformation matrix
projection = np.random.randn(latent_dim, n_features)

# Generate observed features and add noise
train_data = train_latent @ projection + np.random.randn(n_train, n_features) * 2.0
test_data = test_latent @ projection + np.random.randn(n_test, n_features) * 2.0

np.savetxt('/home/user/train_data.csv', train_data, delimiter=',')
np.savetxt('/home/user/test_data.csv', test_data, delimiter=',')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
