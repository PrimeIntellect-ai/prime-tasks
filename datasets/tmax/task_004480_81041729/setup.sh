#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy scipy setuptools

    python3 -c '
import os
import numpy as np
from scipy.signal import savgol_filter

# Create directories
os.makedirs("/app/data", exist_ok=True)
os.makedirs("/app/spec_smooth/spec_smooth", exist_ok=True)

# Generate synthetic spectra
np.random.seed(42)
N, M = 50, 1000
x = np.linspace(0, 10, M)
theoretical = np.zeros((N, M))
noisy = np.zeros((N, M))

for i in range(N):
    # Create a mixture of Gaussians as theoretical spectrum
    mu1, mu2 = np.random.uniform(2, 4), np.random.uniform(6, 8)
    sig1, sig2 = np.random.uniform(0.5, 1.0), np.random.uniform(0.5, 1.0)
    y = np.exp(-0.5 * ((x - mu1)/sig1)**2) + 0.5 * np.exp(-0.5 * ((x - mu2)/sig2)**2)
    y = np.clip(y, 0, None)
    theoretical[i] = y

    # Add noise
    noise = np.random.normal(0, 0.1, M)
    noisy[i] = y + noise

np.save("/app/data/theoretical_spectra.npy", theoretical)
np.save("/app/data/noisy_spectra.npy", noisy)

# Create vendored package setup.py
setup_py = """
from setuptools import setup, find_packages

setup(
    name="spec_smooth",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["numpy", "scipy"]
)
"""
with open("/app/spec_smooth/setup.py", "w") as f:
    f.write(setup_py)

# Create package __init__.py
with open("/app/spec_smooth/spec_smooth/__init__.py", "w") as f:
    f.write("from .core import smooth\n")

# Create package core.py with deliberate bug
core_py = """
import nump as np  # BUG: should be numpy
from scipy.signal import savgol_filter

def smooth(signal, window_length=15, polyorder=3):
    return savgol_filter(signal, window_length, polyorder)
"""
with open("/app/spec_smooth/spec_smooth/core.py", "w") as f:
    f.write(core_py)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
