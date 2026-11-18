#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
n = 1000

F1 = np.random.normal(0, 1, n)
F2 = np.random.normal(5, 2, n)
F3 = np.random.normal(-2, 1.5, n)
F4 = np.random.normal(10, 5, n)

# T is heavily dependent on F3, meaning F3 will be selected
T = -5.5 * F3 + 3.14 + np.random.normal(0, 0.2, n)

df = pd.DataFrame({'F1': F1, 'F2': F2, 'F3': F3, 'F4': F4, 'T': T})
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
