#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest h5py numpy

apt-get install -y build-essential libhdf5-dev

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

# True parameters
A_true = 3.12
D_true = 0.53

x = np.linspace(-10, 10, 200)
t = np.linspace(1, 10, 50)

X, T = np.meshgrid(x, t)
# u_model(x, t) = (A / sqrt(t)) * exp(-(x^2) / (4 * D * t))
U = (A_true / np.sqrt(T)) * np.exp(-(X**2) / (4 * D_true * T))

# Add a tiny bit of noise that doesn't shift the minimum on the specified grid
np.random.seed(42)
U += np.random.normal(0, 0.0001, U.shape)

with h5py.File('/home/user/experimental_data.h5', 'w') as f:
    f.create_dataset('x', data=x, dtype='float64')
    f.create_dataset('t', data=t, dtype='float64')
    f.create_dataset('u', data=U, dtype='float64')
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
