#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import h5py
import numpy as np

os.makedirs("/home/user/data", exist_ok=True)
np.random.seed(42)

for i in range(5):
    with h5py.File(f"/home/user/data/docs_{i}.h5", "w") as f:
        data = np.random.randn(2000, 256).astype(np.float32)
        f.create_dataset("embeddings", data=data)

with h5py.File("/home/user/queries.h5", "w") as f:
    data = np.random.randn(100, 256).astype(np.float32)
    f.create_dataset("queries", data=data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
