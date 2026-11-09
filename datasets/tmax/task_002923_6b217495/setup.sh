#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import h5py

np.random.seed(42)

base_signals = np.random.randn(500, 3)
mixing_matrix = np.random.randn(3, 95)
X = np.dot(base_signals, mixing_matrix)

X += np.random.normal(0, 0.1, X.shape)

X_full = np.zeros((500, 100))

normal_cols = list(range(100))
artifacts = [10, 20, 31, 32, 33]
for idx in artifacts:
    normal_cols.remove(idx)

for i, col_idx in enumerate(normal_cols):
    X_full[:, col_idx] = X[:, i]

X_full[:, 31] = X_full[:, 30]
X_full[:, 32] = X_full[:, 30]
X_full[:, 33] = X_full[:, 30]

with h5py.File('/home/user/sim_data.h5', 'w') as f:
    f.create_dataset('spectra', data=X_full)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
