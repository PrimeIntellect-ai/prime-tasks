#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/sensor_data
    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
os.makedirs('/home/user/sensor_data', exist_ok=True)

timestamps = np.arange(1000)
base_temp = 20.0 + 5.0 * np.sin(timestamps / 50.0)

# Reference
pd.DataFrame({'timestamp': timestamps, 'temperature': base_temp}).to_csv('/home/user/reference.csv', index=False)

# Generate 20 machines
anomalous_dist = [3, 8, 14]
anomalous_cp = [7, 19]

for i in range(1, 21):
    temp = base_temp.copy()

    if i in anomalous_dist:
        # Add offset to increase distance
        temp += 5.0 + np.random.normal(0, 0.5, 1000)
    elif i in anomalous_cp:
        # Add changepoint (high variance in second half)
        temp[:500] += np.random.normal(0, 0.5, 500)
        temp[500:] += np.random.normal(0, 4.0, 500)
    else:
        # Normal
        temp += np.random.normal(0, 0.5, 1000)

    df = pd.DataFrame({'timestamp': timestamps, 'temperature': temp})
    df.to_csv(f'/home/user/sensor_data/machine_{i:02d}.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
