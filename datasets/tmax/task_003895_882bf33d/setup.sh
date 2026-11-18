#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup.py
import numpy as np

# Use deterministic seeds for reproducibility
np.random.seed(42)
baseline = np.random.exponential(scale=10.0, size=1000)
new_version = np.random.exponential(scale=15.0, size=1000)

np.savetxt('/home/user/baseline_latencies.txt', baseline, fmt='%.4f')
np.savetxt('/home/user/new_latencies.txt', new_version, fmt='%.4f')
EOF

    python3 setup.py
    rm setup.py

    chmod -R 777 /home/user
