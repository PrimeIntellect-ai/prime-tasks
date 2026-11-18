#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
# Generate a dataset with some NaNs to test the filtering
data = np.random.normal(loc=0.1, scale=1.2, size=(500, 10))
# Inject some NaNs
data[np.random.rand(*data.shape) < 0.05] = np.nan

df = pd.DataFrame(data, columns=[f'v{i+1}' for i in range(10)])
df.to_csv('/home/user/sim_data.csv', index=False)
EOF
    python3 /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
