#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter nbconvert numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/create_notebook.py
import nbformat as nbf
nb = nbf.v4.new_notebook()
code = """
import numpy as np
# Set explicit seed for reproducible ground truth
rng = np.random.default_rng(42)
# Exponential with lambda=2.0 means scale=0.5
samples = rng.exponential(scale=0.5, size=10000)
np.savetxt('/home/user/samples.txt', samples, fmt='%.6f')
"""
nb['cells'] = [nbf.v4.new_code_cell(code)]
nbf.write(nb, '/home/user/sampler.ipynb')
EOF

    python3 /home/user/create_notebook.py
    rm /home/user/create_notebook.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
