#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
groups = np.random.randint(1, 6, n)
f1 = np.random.poisson(10, n)
f2 = np.random.poisson(20, n)
f3 = np.random.poisson(30, n)
f4 = np.random.poisson(40, n)
f5 = np.random.poisson(50, n)

df = pd.DataFrame({'group_id': groups, 'F1': f1, 'F2': f2, 'F3': f3, 'F4': f4, 'F5': f5})

# Introduce NaNs to cause float casting
for col in ['F1', 'F2', 'F3', 'F4', 'F5']:
    mask = np.random.rand(n) < 0.15
    df.loc[mask, col] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
