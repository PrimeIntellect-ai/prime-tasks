#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

# Set seed for reproducibility
np.random.seed(42)
N, M = 500, 20

# Generate synthetic sensor data
X = np.random.rand(N, M) * 10
# Introduce a strong principal component
X[:, 0] += X[:, 1] * 2.5 - X[:, 2] * 1.5 + X[:, 3] * 0.5
X[:, 4] -= X[:, 1] * 1.2

# Write out the CSV file as it will appear in the environment
np.savetxt("/home/user/sensor_data.csv", X, delimiter=",", fmt="%.6f")

# Calculate the canonical answer according to the task rules
# 1. Mean center
X_c = X - np.mean(X, axis=0)
# 2. Covariance matrix (N-1)
C = np.dot(X_c.T, X_c) / (N - 1)

# 3. Power Iteration
v = np.ones(M)
for _ in range(100):
    w = np.dot(C, v)
    v = w / np.linalg.norm(w, ord=2)

# 4. Sign Determinism
if v[0] < 0:
    v = -v

# 5. Output expectation
expected_output = "\n".join([f"{val:.6f}" for val in v]) + "\n"
with open("/home/user/expected_first_component.txt", "w") as f:
    f.write(expected_output)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
