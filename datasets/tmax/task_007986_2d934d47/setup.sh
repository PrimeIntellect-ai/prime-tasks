#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(10)
N = 400
x = np.random.uniform(0, 1, N)
y = np.random.uniform(0, 1, N)
# Create a function with high variance in specific regions
value = np.sin(2 * np.pi * x) * np.cos(2 * np.pi * y)
# Add targeted noise to region around x=0.8, y=0.8 (index 3*4 + 3 = 15) and x=0.2, y=0.8 (index 0*4 + 3 = 3)
noise = np.random.normal(0, 0.1, N)
noise[(x > 0.75) & (y > 0.75)] += np.random.normal(0, 0.8, sum((x > 0.75) & (y > 0.75)))
noise[(x < 0.25) & (y > 0.75)] += np.random.normal(0, 0.6, sum((x < 0.25) & (y > 0.75)))
value += noise

df = pd.DataFrame({'x': x, 'y': y, 'value': value})
df.to_csv('/home/user/initial_data.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
