#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib fastapi uvicorn flask

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/artifacts.csv
artifact_id,f1,f2,f3,f4,f5
art_1,0.1,0.2,0.3,0.4,0.5
art_2,0.1,0.2,0.3,0.4,0.49
art_3,0.9,0.8,0.7,0.6,0.5
art_4,0.15,0.25,0.35,0.45,0.55
art_5,0.88,0.82,0.68,0.62,0.51
EOF

    mkdir -p /app/mlops-artifact-utils/mlops_artifact_utils
    cat << 'EOF' > /app/mlops-artifact-utils/setup.py
from setuptools import setup, find_packages
setup(name='mlops-artifact-utils', version='1.0.0', packages=find_packages(), install_requires=['numpy', 'matplotlib'])
EOF

    cat << 'EOF' > /app/mlops-artifact-utils/mlops_artifact_utils/__init__.py
from .math_ops import cosine_similarity_matrix
from .plot_ops import plot_pca
EOF

    cat << 'EOF' > /app/mlops-artifact-utils/mlops_artifact_utils/math_ops.py
import numpy as np
def cosine_similarity_matrix(X):
    norms = np.linalg.norm(X, axis=1)
    return np.dot(X, X.T) / (norms[:, np.newaxis] + norms[np.newaxis, :])
EOF

    cat << 'EOF' > /app/mlops-artifact-utils/mlops_artifact_utils/plot_ops.py
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
import numpy as np

def plot_pca(X, output_path):
    # dummy PCA for visualization
    mean = np.mean(X, axis=0)
    centered = X - mean
    U, S, Vt = np.linalg.svd(centered, full_matrices=False)
    pcs = np.dot(centered, Vt.T[:, :2])
    plt.scatter(pcs[:, 0], pcs[:, 1])
    plt.savefig(output_path)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
