#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip

    # Pre-install dependencies to avoid timeouts and ensure availability
    pip3 install --no-cache-dir pytest numpy pandas scikit-learn flask joblib

    # Create directories
    mkdir -p /app/feature_server_pkg-1.2.0/feature_server_pkg
    mkdir -p /app/data

    # Create vendored package files
    cat << 'EOF' > /app/feature_server_pkg-1.2.0/Makefile
install:
	python3.5 setup.py install
EOF

    cat << 'EOF' > /app/feature_server_pkg-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='feature_server_pkg',
    version='1.2.0',
    packages=find_packages(),
    install_requires=['flask', 'numpy', 'scikit-learn]
)
EOF

    cat << 'EOF' > /app/feature_server_pkg-1.2.0/feature_server_pkg/__init__.py
class AppServer:
    pass
EOF

    # Generate raw_features.csv
    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(42)
data = np.random.randn(100, 50)
columns = [f'f_{i}' for i in range(50)]
df = pd.DataFrame(data, columns=columns)
df.to_csv('/app/data/raw_features.csv', index=False)
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
