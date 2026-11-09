#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
np.random.seed(123)
data = np.random.normal(loc=0.45, scale=0.08, size=200)
data = np.clip(data, 0.0, 1.0)
np.save('/home/user/gc_data.npy', data)
EOF
    python3 /home/user/setup_data.py

    chmod -R 777 /home/user
