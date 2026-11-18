#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
t = np.linspace(0, 10, 1000, endpoint=False) # 100 Hz sampling, 1000 points
stable = np.random.normal(0, 0.1, 1000)
# Inject an 8 Hz oscillation to simulate resonance + some noise and slight offset
unstable = 2.0 * np.sin(2 * np.pi * 8 * t) + np.random.normal(0, 0.2, 1000) + 0.05

df = pd.DataFrame({'time': t, 'stable_err': stable, 'unstable_err': unstable})
df.to_csv('/home/user/sim_data.csv', index=False)
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
