#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user/sim_data', exist_ok=True)
np.random.seed(42)

for i in range(1, 51):
    t = np.linspace(0, 10, 101)
    v = np.sin(t) + 2.0 + np.random.normal(0, 1.5, 101) 
    with open(f'/home/user/sim_data/sim_{i}.csv', 'w') as f:
        f.write("t,v\n")
        for tj, vj in zip(t, v):
            f.write(f"{tj:.2f},{vj:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
