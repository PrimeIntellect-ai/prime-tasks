#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
np.random.seed(42)
X = np.random.randn(1000, 5) * 5
np.savetxt('/home/user/raw_features.csv', X, delimiter=',')
weights = np.random.randn(5)
np.save('/home/user/weights.npy', weights)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
