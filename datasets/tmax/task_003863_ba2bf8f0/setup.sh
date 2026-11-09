#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base-core
    pip3 install pytest numpy scipy h5py

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

np.random.seed(42)
data = np.zeros((200, 1000))
for i in range(200):
    if i % 2 == 0:
        data[i] = np.random.normal(loc=0, scale=1, size=1000)
    else:
        # slightly skewed
        data[i] = np.random.lognormal(mean=0, sigma=0.5, size=1000)

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('empirical_data', data=data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
