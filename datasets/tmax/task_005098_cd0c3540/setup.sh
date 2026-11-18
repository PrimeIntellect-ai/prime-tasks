#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import os

# 1. Generate Data
np.random.seed(42)
A = np.random.normal(0, 1, (100, 50))
B = np.random.normal(0.5, 1, (100, 50))

np.savez('/home/user/embeddings.npz', A=A, B=B)

# 2. Create the broken script
broken_script = """import numpy as np
import matplotlib
matplotlib.use('TkAgg') # BUG: Will fail in headless environment
import matplotlib.pyplot as plt
from scipy import stats

# Load data
data = np.load('/home/user/embeddings.npz')
A = data['A']
B = data['B']
X = np.vstack((A, B))

# Perform PCA via SVD to 2D
# BUG: Data is not mean-centered before SVD!
U, S, Vt = np.linalg.svd(X, full_matrices=False)
X_pca = X @ Vt.T[:, :2]

A_pca = X_pca[:len(A)]
B_pca = X_pca[len(A):]

# Plotting
plt.scatter(A_pca[:,0], A_pca[:,1], label='Model A')
plt.scatter(B_pca[:,0], B_pca[:,1], label='Model B')
plt.legend()
plt.savefig('/home/user/pca_plot.png')

# TODO: Calculate Euclidean distance between 2D centroids and save to /home/user/centroid_distance.txt
# TODO: Calculate independent 2-sample t-test p-value on PC1 and save to /home/user/p_value.txt
"""

with open('/home/user/analyze_artifacts.py', 'w') as f:
    f.write(broken_script)

os.chmod('/home/user/analyze_artifacts.py', 0o755)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
