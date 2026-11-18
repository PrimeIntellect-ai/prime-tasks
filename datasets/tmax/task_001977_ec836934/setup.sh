#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

data = [
    (0.0, 1.05),
    (0.5, 0.72),
    (1.2, 0.48),
    (2.5, 0.21),
    (4.0, 0.11),
    (5.5, 0.05)
]
np.random.seed(42)
np.random.shuffle(data)

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/raw_observations.txt', 'w') as f:
    for t, val in data:
        f.write(f"time_point:{t}|concentration:{val}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
