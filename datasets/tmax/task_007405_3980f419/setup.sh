#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(101)
run1_data = np.clip(np.random.normal(32, 4, (100, 50)), 0, 40).astype(int)
run2_data = np.clip(np.random.normal(29, 6, (120, 50)), 0, 40).astype(int)

pd.DataFrame(run1_data).to_csv('/home/user/run1_scores.csv', index=False, header=False)
pd.DataFrame(run2_data).to_csv('/home/user/run2_scores.csv', index=False, header=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
