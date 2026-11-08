#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

np.random.seed(123)
data1 = np.random.randn(1000, 50).astype(np.float32)
# Simulate FP reduction order differences by adding tiny noise
data2 = data1 + np.random.uniform(-1e-6, 1e-6, size=data1.shape).astype(np.float32)

with h5py.File('/home/user/sim_v1.h5', 'w') as f:
    f.create_dataset('features', data=data1)

with h5py.File('/home/user/sim_v2.h5', 'w') as f:
    f.create_dataset('features', data=data2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
