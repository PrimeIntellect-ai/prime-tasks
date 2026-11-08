#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy matplotlib

useradd -m -s /bin/bash user || true

mkdir -p /home/user/sim_data

cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

data_dir = "/home/user/sim_data"
os.makedirs(data_dir, exist_ok=True)

np.random.seed(42)

for i in range(50):
    data = np.random.lognormal(mean=0.0, sigma=2.0, size=(100000, 3)).astype(np.float32)
    filename = os.path.join(data_dir, f"run_{i:02d}.npy")
    np.save(filename, data)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
