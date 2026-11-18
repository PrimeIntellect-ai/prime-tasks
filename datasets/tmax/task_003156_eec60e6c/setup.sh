#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/scripts
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/data/raw.txt
Hello, world! This is a test dataset.
Data science involves linear algebra, tokenization, and environments.
Testing 1, 2, 3... The quick brown fox jumps!
EOF

    cat << 'EOF' > /home/user/scripts/analyze.py
import sys
import os
import numpy as np
import matplotlib.pyplot as plt

# Ensure it's running in headless mode via environment variable
if os.environ.get('MPLBACKEND') != 'Agg':
    print("Error: Matplotlib backend not set to headless mode (Agg).")
    sys.exit(1)

with open('/home/user/data/tokens.txt', 'r') as f:
    tokens = [line.strip() for line in f if line.strip()]

unique_tokens = list(set(tokens))
n = len(unique_tokens)

# Dummy linear algebra operation (simulate co-occurrence matrix)
np.random.seed(42)
matrix = np.random.rand(n, n)
matrix = (matrix + matrix.T) / 2 # symmetric
eigenvalues, _ = np.linalg.eigh(matrix)

# Save metrics
with open('/home/user/artifacts/eigen_metrics.txt', 'w') as f:
    f.write(f"Vocab size: {n}\n")
    f.write(f"Max Eigenvalue: {np.max(eigenvalues):.4f}\n")

# Plot
plt.figure()
plt.plot(eigenvalues)
plt.title("Eigenvalues")
plt.savefig('/home/user/artifacts/plot.png')
EOF

    chmod +x /home/user/scripts/analyze.py
    chmod -R 777 /home/user
