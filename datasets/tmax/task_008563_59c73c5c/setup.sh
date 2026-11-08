#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
os.makedirs('/home/user/raw_data', exist_ok=True)

for i in range(3):
    n_rows = 10000
    timestamps = np.random.randint(0, 86400 * 5, size=n_rows)
    sensor_ids = np.random.choice(['sensor_A', 'sensor_B', 'sensor_C'], size=n_rows)

    # Create values that will cause precision loss in float32 (mix of huge and tiny numbers)
    values = []
    for _ in range(n_rows):
        if np.random.rand() < 0.1:
            values.append(1e6 + np.random.rand()) # Anomaly
        elif np.random.rand() < 0.2:
            values.append(-50.0) # Anomaly
        else:
            # Alternating large/small values to trigger catastrophic cancellation in float32
            values.append(10000.0 if np.random.rand() < 0.5 else 0.0001)

    df = pd.DataFrame({
        'timestamp': timestamps,
        'sensor_id': sensor_ids,
        'value': values
    })
    df.to_csv(f'/home/user/raw_data/chunk_{i}.csv', index=False)
EOF

    python3 /home/user/generate_data.py

    chmod -R 777 /home/user
