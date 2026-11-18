#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    # Create directories
    mkdir -p /app/spectro-tools-0.4.2/spectro_tools
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    # Create spectro-tools package files
    cat << 'EOF' > /app/spectro-tools-0.4.2/setup.py
from setuptools import setup, find_packages
setup(
    name='spectro-tools',
    version='0.4.2',
    packages=find_packages(),
    install_requires=['numpy', 'scipy'],
)
EOF

    cat << 'EOF' > /app/spectro-tools-0.4.2/spectro_tools/__init__.py
from .baseline import remove_baseline
EOF

    cat << 'EOF' > /app/spectro-tools-0.4.2/spectro_tools/baseline.py
import numpy as np
from scipy.sparse.linalg import spsolve

def remove_baseline(y, lam=1e5, p=0.01, itermax=10):
    L = len(y)
    D = sparse.diags([1, -2, 1], [0, -1, -2], shape=(L, L-2))
    D = lam * D.dot(D.transpose())
    w = np.ones(L)
    for i in range(itermax):
        W = sparse.diags(w, 0, shape=(L, L))
        Z = W + D
        z = spsolve(Z, w*y)
        w = p * (y > z) + (1-p) * (y < z)
    return y - z
EOF

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

def generate_clean(path, n=50):
    for i in range(n):
        x = np.linspace(400, 4000, 1000)
        y = np.exp(-((x - 1500) / 100)**2) * 100 + 50 + np.random.poisson(10, 1000) * 0.1
        pd.DataFrame({'wavelength': x, 'intensity': y}).to_csv(os.path.join(path, f'clean_{i:03d}.csv'), index=False)

def generate_evil(path, n=50):
    for i in range(n):
        x = np.linspace(400, 4000, 1000)
        y = np.exp(-((x - 1500) / 100)**2) * 100 + 50 + np.random.poisson(10, 1000) * 0.1
        if i < n // 2:
            # High frequency spike
            idx = np.random.randint(100, 900)
            y[idx] += 10000.0
            y[idx+1] -= 10000.0
        else:
            # NaN causing value
            y[500] = np.nan
        pd.DataFrame({'wavelength': x, 'intensity': y}).to_csv(os.path.join(path, f'evil_{i:03d}.csv'), index=False)

generate_clean('/app/data/clean', 25)
generate_evil('/app/data/evil', 25)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
