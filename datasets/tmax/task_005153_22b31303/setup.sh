#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev gawk
pip3 install pytest numpy

mkdir -p /home/user/workspace

python3 -c '
import os
import numpy as np

workspace = "/home/user/workspace"
os.makedirs(workspace, exist_ok=True)

# 1. Create the singular covariance matrix
cov_matrix = np.array([
    [1.0, 1.0, 1.0],
    [1.0, 1.0, 1.0],
    [1.0, 1.0, 1.0]
])
np.savetxt(os.path.join(workspace, "cov_matrix.txt"), cov_matrix, fmt="%.1f")

# 2. Generate exactly 1000 standard normal samples deterministically
np.random.seed(42)
z_samples = np.random.randn(1000, 3)
np.savetxt(os.path.join(workspace, "z_samples.txt"), z_samples, fmt="%.6f")

# 3. Compute the expected answer to verify against
cov_reg = cov_matrix + np.eye(3) * 1e-5
L = np.linalg.cholesky(cov_reg)
mu = np.array([0.5, 1.0, 2.0])

dt = 0.01
steps = 200

final_y_values = []
for z in z_samples:
    theta = mu + L.dot(z)

    # ODE Simulation
    y = 5.0
    for i in range(steps):
        t = i * dt
        dy = -theta[0] * y + theta[1] * np.sin(theta[2] * t)
        y += dy * dt
    final_y_values.append(y)

avg_y = np.mean(final_y_values)
expected_output = f"{avg_y:.4f}"

with open(os.path.join(workspace, ".expected_result.txt"), "w") as f:
    f.write(expected_output)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
