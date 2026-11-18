#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np

np.random.seed(42)
# Base simulation results
base = np.random.normal(10.0, 2.0, 1000)
single = base
# Introduce floating point reduction drift
multi = base + np.random.uniform(-0.1, 0.1, 1000)

np.savetxt('/home/user/single_thread.csv', single, fmt='%.6f')
np.savetxt('/home/user/multi_thread.csv', multi, fmt='%.6f')
EOF
    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
