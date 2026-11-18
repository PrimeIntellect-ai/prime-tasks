#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev libgsl-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

# Create the data
np.random.seed(42)
X = np.random.randn(50, 5)
X_dependent = X @ np.random.randn(5, 5) + 1e-4 * np.random.randn(50, 5)
data = np.hstack((X, X_dependent))

os.makedirs("/home/user", exist_ok=True)
np.savetxt("/home/user/spectra.csv", data, delimiter=",")

# Calculate the expected result
C = np.cov(data, rowvar=False)
# SVD of C + 0.01 I
C1 = C + 0.01 * np.eye(10)
U, S, Vh = np.linalg.svd(C1)
cond1 = S.max() / S.min()

if cond1 > 500:
    lam = 0.5
else:
    lam = 0.01

C_reg = C + lam * np.eye(10)
L = np.linalg.cholesky(C_reg)
trace_L = np.trace(L)

# Expected output string
expected_output = f"Lambda: {lam:.4f}, Trace: {trace_L:.4f}\n"
with open("/home/user/expected_result.txt", "w") as f:
    f.write(expected_output)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
