#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import csv

np.random.seed(123)
t = np.arange(11, dtype=float)
y_true = 100 * np.exp(-0.3 * t)
y_obs = y_true + np.random.normal(0, 2.0, size=len(t))

with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['t', 'y_obs'])
    for i in range(len(t)):
        writer.writerow([t[i], y_obs[i]])
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
