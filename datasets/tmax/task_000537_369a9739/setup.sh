#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy scipy flask jupyterlab setuptools

    mkdir -p /app/prot_integrator/prot_integrator

    cat << 'EOF' > /app/prot_integrator/setup.py
from setuptools import setup, find_packages

setup(
    name='prot_integrator',
    version='1.2.0',
    packages=find_packages(),
    install_requires=['numpy'],
)
EOF

    cat << 'EOF' > /app/prot_integrator/prot_integrator/__init__.py
from .core import simulate
EOF

    cat << 'EOF' > /app/prot_integrator/prot_integrator/core.py
import numpy as np

def simulate(pdb_path, steps=1000):
    np.random.seed(42)
    dt = 0.1
    for _ in range(steps):
        error = np.random.rand()
        if error > 0.5:
            dt = dt * 1.5  # Deliberate bug

    if dt > 1000:
        return np.full((10, 10), np.nan)
    else:
        return np.random.rand(10, 10)
EOF

    mkdir -p /home/user/data/pdbs
    cat << 'EOF' > /home/user/data/pdbs/1A2B.pdb
ATOM      1  N   ALA A   1      -0.525   1.362   0.000  1.00  0.00           N
ATOM      2  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      3  C   ALA A   1       1.520   0.000   0.000  1.00  0.00           C
ATOM      4  O   ALA A   1       2.100   1.080   0.000  1.00  0.00           O
ATOM      5  CB  ALA A   1      -0.525  -0.721  -1.216  1.00  0.00           C
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app/prot_integrator
    chmod -R 777 /home/user
