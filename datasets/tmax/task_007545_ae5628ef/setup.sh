#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

# Initial data
data = np.array([0.2, 0.8, 0.4, 0.9, 0.3, 0.7, 0.5, 0.6, 0.1, 0.9], dtype=np.float64)

with h5py.File('/home/user/gc_data.h5', 'w') as f:
    f.create_dataset('/gc_content', data=data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
