#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

# Generate stable reference residuals
ref_res = np.random.gamma(shape=2.0, scale=0.5, size=1000)
pd.DataFrame({'residual': ref_res}).to_csv('/home/user/reference_residuals.csv', index=False)

# Generate trajectories
n_traj = 50
points_per_traj = 100

data = []
ids = []
times = []

# Random 5D projection matrix (orthogonal)
V_true, _ = np.linalg.qr(np.random.randn(5, 5))

for i in range(n_traj):
    t = np.linspace(-2, 3, points_per_traj)
    z1 = t
    z2 = 0.5 * z1**3 - 1.2 * z1**2 + 0.1 * z1 + 0.5

    # Add noise
    if i in [2, 7, 14, 23, 31, 38, 45]:
        # Divergent trajectories
        noise = np.random.randn(points_per_traj, 2) * 2.5
    else:
        # Stable
        noise = np.random.randn(points_per_traj, 2) * 0.3

    Z = np.column_stack([z1, z2]) + noise
    Z_5d = np.dot(Z, V_true[:2, :])

    for j in range(points_per_traj):
        ids.append(i)
        times.append(t[j])
        data.append(Z_5d[j])

df = pd.DataFrame(data, columns=['x1', 'x2', 'x3', 'x4', 'x5'])
df.insert(0, 'time', times)
df.insert(0, 'id', ids)

df.to_csv('/home/user/trajectories.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
