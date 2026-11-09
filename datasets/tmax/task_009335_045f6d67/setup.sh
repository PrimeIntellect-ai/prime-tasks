#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np

np.random.seed(42)
N_points = 10000
x = np.random.uniform(0, 1, N_points)
time = 10.0 + 5.0 * np.sin(2 * np.pi * x) + np.random.normal(0, 1.0, N_points)

with open('/home/user/profiling_data.csv', 'w') as f:
    f.write("x,time\n")
    for i in range(N_points):
        f.write(f"{x[i]:.6f},{time[i]:.6f}\n")
EOF

    python3 /home/user/setup_data.py

    chmod -R 777 /home/user
