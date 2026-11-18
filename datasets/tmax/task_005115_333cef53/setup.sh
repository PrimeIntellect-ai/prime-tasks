#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy setuptools

    # Create directories
    mkdir -p /app/root_finder_pkg/root_finder_pkg
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create setup.py with syntax error
    cat << 'EOF' > /app/root_finder_pkg/setup.py
from setuptools import setup, find_packages
setup(
    name="root_finder_pkg",
    version="1.0.0"
    packages=find_packages(),
)
EOF

    # Create dummy __init__.py
    touch /app/root_finder_pkg/root_finder_pkg/__init__.py

    # Generate corpora
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

np.random.seed(42)

for i in range(10):
    # Clean data
    a = np.random.uniform(-10, 10, (100, 100))
    x = np.random.uniform(-5, 5, (100, 100))
    b = -(x**3 + a * x)
    np.savez(f'/app/corpus/clean/clean_{i}.npz', x=x, a=a, b=b)

    # Evil data (introduce error)
    a_e = np.copy(a)
    x_e = np.copy(x)
    b_e = np.copy(b)
    if i % 2 == 0:
        b_e[50, 50] += 0.5  # Tolerance violation
    else:
        x_e[10, 10] = np.nan # NaN violation
    np.savez(f'/app/corpus/evil/evil_{i}.npz', x=x_e, a=a_e, b=b_e)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Ensure permissions for /app
    chmod -R 777 /app

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
