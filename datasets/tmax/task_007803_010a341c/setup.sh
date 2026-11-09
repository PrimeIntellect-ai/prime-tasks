#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
data = np.random.standard_cauchy(1000) * 2.0 + 5.0
ref = np.random.standard_cauchy(500) * 2.0 + 5.0

np.savetxt('/home/user/data.txt', data, fmt='%.8f')
np.savetxt('/home/user/reference.txt', ref, fmt='%.8f')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
