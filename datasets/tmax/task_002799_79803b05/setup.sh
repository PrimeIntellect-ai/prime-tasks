#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

su - user -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
ln -s /home/user/.cargo/bin/* /usr/local/bin/

mkdir -p /home/user/mlops/data

cat << 'EOF' > /tmp/setup_data.py
import json
import os
import numpy as np

np.random.seed(42)

data_dir = "/home/user/mlops/data"
os.makedirs(data_dir, exist_ok=True)

P = np.array([0.5, -0.5, 0.5, -0.5])

for i in range(1, 51):
    id_str = f"exp_{i:02d}"
    weights = np.random.uniform(-1.0, 1.0, 4).tolist()

    # Generate an error rate loosely correlated with the projected weight + noise
    proj_weight = np.dot(np.array(weights), P)
    error_rate = 0.5 + 0.2 * proj_weight + np.random.normal(0, 0.05)
    error_rate = max(0.01, min(0.99, error_rate)) # clamp

    exp_data = {
        "id": id_str,
        "weights": weights,
        "error_rate": float(error_rate)
    }

    with open(os.path.join(data_dir, f"{id_str}.json"), "w") as f:
        json.dump(exp_data, f)
EOF

python3 /tmp/setup_data.py

chmod -R 777 /home/user
