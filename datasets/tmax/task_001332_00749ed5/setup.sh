#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app/data
    mkdir -p /app/vendored/pydynsim-1.2.0/pydynsim

    # Create dummy PDB file
    cat << 'EOF' > /app/data/protein.pdb
ATOM      1  N   ALA A   1      11.104  13.727  15.654  1.00  0.00           N  
ATOM      2  CA  ALA A   1      10.426  13.111  14.527  1.00  0.00           C  
ATOM      3  C   ALA A   1       9.610  11.916  14.996  1.00  0.00           C  
ATOM      4  O   ALA A   1       9.851  11.309  16.038  1.00  0.00           O  
ATOM      5  CB  ALA A   1      11.458  12.673  13.486  1.00  0.00           C  
EOF

    # Create setup.py
    cat << 'EOF' > /app/vendored/pydynsim-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name="pydynsim",
    version="1.2.0",
    packages=find_packages(),
    install_requires=["numpy"],
)
EOF

    # Create integrator.py
    cat << 'EOF' > /app/vendored/pydynsim-1.2.0/pydynsim/integrator.py
def get_dt():
    dt_old = 0.01
    error = 1.0
    tolerance = 1e-4
    # Adapt step size
    dt_new = dt_old * (error / tolerance)**0.5
    return dt_new
EOF

    # Create __init__.py
    cat << 'EOF' > /app/vendored/pydynsim-1.2.0/pydynsim/__init__.py
import numpy as np
from .integrator import get_dt

def simulate(filepath, steps=5000):
    dt = get_dt()
    # If dt is too large (meaning the buggy logic was used), diverge
    if dt > 0.05:
        return np.full((steps, 10, 3), np.nan)

    # If fixed, return stable oscillation
    # The prompt states dt averages out to exactly 0.01 picoseconds for the FFT
    actual_dt = 0.01
    t = np.arange(steps) * actual_dt

    arr = np.zeros((steps, 10, 3))
    # Atom index 4, Z-axis (index 2) oscillates at 15.625 THz
    arr[:, 4, 2] = np.sin(2 * np.pi * 15.625 * t)
    return arr
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
