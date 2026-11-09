#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy emcee setuptools

    # Create vendored package directory and files
    mkdir -p /app/vendored/astro_core/astro_core

    cat << 'EOF' > /app/vendored/astro_core/setup.py
from setuptools import setup, find_packages
setup(name='astro_core', version='1.0.0', packages=find_packages())
EOF

    cat << 'EOF' > /app/vendored/astro_core/astro_core/__init__.py
from .calc import compute_derivative
EOF

    cat << 'EOF' > /app/vendored/astro_core/astro_core/calc.py
imprt numpy as np  # Deliberate typo here

def compute_derivative(x, y):
    return np.gradient(y, x)
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate the HDF5 corpora
    cat << 'EOF' > /tmp/generate_data.py
import os
import h5py
import numpy as np

os.makedirs('/home/user/data/clean', exist_ok=True)
os.makedirs('/home/user/data/evil', exist_ok=True)

x = np.linspace(0, 10, 100)
np.random.seed(42)

# Clean 1
with h5py.File('/home/user/data/clean/c1.h5', 'w') as f:
    f.create_dataset('time', data=x)
    f.create_dataset('flux', data=2.0 * x**2 - 5.0 * x + 10.0 + np.random.normal(0, 0.1, 100))

# Clean 2
with h5py.File('/home/user/data/clean/c2.h5', 'w') as f:
    f.create_dataset('time', data=x)
    f.create_dataset('flux', data=0.8 * x**2 + 2.0 * x + 1.0 + np.random.normal(0, 0.1, 100))

# Evil 1 (Spike - derivative > 50)
y_spike = 1.0 * x**2 + x + 1.0
y_spike[50] += 100.0
with h5py.File('/home/user/data/evil/e1_spike.h5', 'w') as f:
    f.create_dataset('time', data=x)
    f.create_dataset('flux', data=y_spike)

# Evil 2 (Negative a - posterior median a < 0)
with h5py.File('/home/user/data/evil/e2_neg.h5', 'w') as f:
    f.create_dataset('time', data=x)
    f.create_dataset('flux', data=-2.0 * x**2 + 5.0 * x + 10.0 + np.random.normal(0, 0.1, 100))
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /app/vendored
    chmod -R 777 /home/user
