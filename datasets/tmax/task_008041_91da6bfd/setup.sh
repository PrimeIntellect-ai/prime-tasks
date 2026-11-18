#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(999)
n_rows = 500
states = np.random.choice(['ACTIVE', 'IDLE', 'MAINTENANCE'], n_rows, p=[0.6, 0.3, 0.1])
f1 = np.random.normal(5.0, 1.5, n_rows)
f2 = f1 * 0.5 + np.random.normal(0, 0.5, n_rows)
f3 = np.random.normal(-2.0, 3.0, n_rows)

df = pd.DataFrame({
    'timestamp': pd.date_range(start='2023-01-01', periods=n_rows, freq='h'),
    'sensor_state': states,
    'f1': f1,
    'f2': f2,
    'f3': f3
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
