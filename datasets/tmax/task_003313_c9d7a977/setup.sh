#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np

rng = np.random.default_rng(42)
data1 = rng.normal(2, 0.5, 700)
data2 = rng.normal(5, 0.8, 300)
data = np.concatenate([data1, data2])
np.savetxt('/home/user/events.csv', data, fmt='%.5f')
EOF
    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
