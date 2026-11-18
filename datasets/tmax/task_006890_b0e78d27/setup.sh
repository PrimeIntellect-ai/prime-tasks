#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

data = {
    'timestamp': ['2023-10-01T10:00:00', '2023-10-01T10:01:00', '2023-10-01T10:02:00', 
                  '2023-10-01T10:03:00', '2023-10-01T10:04:00', '2023-10-01T10:05:00',
                  '2023-10-01T10:06:00'],
    'temperature': [20.0, 22.0, np.nan, 32.0, 40.0, np.nan, 62.0],
    'pressure': [1013.25, np.nan, 1011.00, 1009.50, np.nan, 1005.00, 1002.25]
}
df = pd.DataFrame(data)
df.to_csv('/home/user/raw_telemetry.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
