#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest numpy mpi4py

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np

N = 4194304
t = np.arange(N)
np.random.seed(42)
signal = np.sin(2 * np.pi * 1024 * t / N) + 0.1 * np.random.randn(N)
np.save('/home/user/data/signal.npy', signal)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
