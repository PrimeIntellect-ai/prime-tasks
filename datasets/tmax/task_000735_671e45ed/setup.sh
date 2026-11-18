#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py setuptools

    python3 << 'EOF'
import os
import h5py
import numpy as np

# Create directories
os.makedirs("/app/data", exist_ok=True)
os.makedirs("/app/vendor/biomatrix-0.1.0/biomatrix", exist_ok=True)

# Generate HDF5 with near-singular matrices
with h5py.File("/app/data/spectra.h5", "w") as f:
    np.random.seed(42)
    for i in range(50):
        # Create a 20x20 rank-15 matrix (singular)
        A = np.random.randn(20, 15)
        M = A @ A.T  # Positive semi-definite but singular
        f.create_dataset(f"seq_{i}", data=M)

# Create the vendored package files
setup_py = """
from setuptools import setup, find_packages
setup(
    name='biomatrix',
    version='0.1.0',
    packages=find_packages(),
    install_requires=['numpy']
)
"""
with open("/app/vendor/biomatrix-0.1.0/setup.py", "w") as f:
    f.write(setup_py)

__init___py = ""
with open("/app/vendor/biomatrix-0.1.0/biomatrix/__init__.py", "w") as f:
    f.write(__init___py)

solver_py = """
import numpy as np

def factorize_signal(matrix):
    # TODO: matrix from MC simulation might be near-singular.
    # Needs Tikhonov regularization (add 1e-5 to diagonal) to avoid LinAlgError.
    L = np.linalg.cholesky(matrix)
    return L
"""
with open("/app/vendor/biomatrix-0.1.0/biomatrix/solver.py", "w") as f:
    f.write(solver_py)

# Set permissions
os.system("chmod -R 777 /app")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
