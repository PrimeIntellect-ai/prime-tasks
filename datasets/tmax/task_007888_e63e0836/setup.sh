#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(0)
p_true = [0.3, 0.2, 0.2, 0.3]
data = np.random.choice([0, 1, 2, 3], size=(1000, 50), p=p_true)
np.save('/home/user/sequences.npy', data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
