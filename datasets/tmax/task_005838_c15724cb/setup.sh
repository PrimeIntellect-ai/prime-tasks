#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/setup.py
import numpy as np
import scipy.linalg
import os

os.makedirs('/home/user/pipeline', exist_ok=True)

# Generate near-singular spectral data
np.random.seed(123)
N_samples = 200
N_features = 20
X = np.random.randn(N_samples, N_features)
# Induce extreme collinearity to make covariance matrix near-singular
X[:, 19] = X[:, 0] + X[:, 1] * 0.5 + np.random.randn(N_samples) * 1e-7

np.savetxt('/home/user/pipeline/spectra.csv', X, delimiter=',')

# Generate target vector
y = np.random.randn(N_features)
np.savetxt('/home/user/pipeline/target.csv', y, delimiter=',')

# Create buggy script
buggy_code = """import numpy as np
import scipy.linalg

def main():
    X = np.loadtxt('/home/user/pipeline/spectra.csv', delimiter=',')
    y = np.loadtxt('/home/user/pipeline/target.csv', delimiter=',')

    # Compute covariance matrix
    C = np.cov(X, rowvar=False)

    # This will fail due to near-singularity
    L = scipy.linalg.cholesky(C, lower=True)

    # Solve system (incomplete in buggy script)
    # w = ...

if __name__ == "__main__":
    main()
"""

with open('/home/user/pipeline/process_spectra.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /home/user/pipeline/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
