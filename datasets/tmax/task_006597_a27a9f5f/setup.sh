#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow fastparquet

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

times = np.arange(1600000000, 1600000200, 10) # 20 timestamps
dfA = pd.DataFrame({'timestamp': times, 'val_A': np.random.randn(20)})
dfB = pd.DataFrame({'timestamp': times, 'val_B': np.random.randn(20) * 2 + dfA['val_A']})
dfC = pd.DataFrame({'timestamp': times, 'val_C': np.random.randn(20) - dfA['val_A']})

# Drop different rows to force meaningful inner join
dfA = dfA.drop([2, 8, 15])
dfB = dfB.drop([5, 15, 18])
dfC = dfC.drop([8, 9, 19])

dfA.to_csv('/home/user/data/sensor_A.csv', index=False)
dfB.to_csv('/home/user/data/sensor_B.csv', index=False)
dfC.to_csv('/home/user/data/sensor_C.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
